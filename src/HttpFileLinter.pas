(* HttpFileLinter - static checks on a parsed THttpFile, reported as warnings.

  THttpFileLinter runs a list of rules (THttpLintRule) over a THttpLintContext,
  an index of the file built once: every double-brace expression of every raw
  value with its position. A rule only reads the context and appends
  diagnostics, so adding a check means writing one rule class and AddRule.

  Built-in rules (rule ids in brackets):
    duplicate request names ..... [lint-duplicate-request]
    variables that are never used [lint-unused-variable]
    unresolved placeholders ..... [lint-unresolved-placeholder]
                                  (unknown names, unknown functions, malformed
                                  request references)
    circular references ......... [lint-circular-reference]
                                  (variables and requests that depend on each
                                  other, through values or through responses)
  Every diagnostic has severity hsWarning and the range of the expression or
  declaration. Pass the parser's Functions and Scripting registries so that
  registered functions and objects are not reported as unresolved. *)
unit HttpFileLinter;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, StrUtils, HttpFileAST, HttpFileFunctions, HttpFileScripting,
  HttpFileReferences;

type
  TLintOwnerKind = (okVariable, okEndpoint);

  { one double-brace expression found in a raw value }
  TLintExpression = record
    Inner: string;   // trimmed text between the braces
    Raw: string;     // the expression with its braces
    Row: Integer;
    Column: Integer;
    OwnerKind: TLintOwnerKind;
    OwnerIndex: Integer; // index in THttpFile.Variables or THttpFile.Endpoints
  end;

  TLintExpressionArray = array of TLintExpression;

  THttpLintContext = class
  private
    FFile: THttpFile;
    FFunctions: THttpFunctionRegistry;
    FObjects: TScriptObjectRegistry;
    FExpressions: TLintExpressionArray;
    procedure AddExpressions(const AText: string; ARow, AColumn: Integer;
      AKind: TLintOwnerKind; AIndex: Integer);
    procedure Collect;
  public
    constructor Create(AFile: THttpFile; AFunctions: THttpFunctionRegistry;
      AObjects: TScriptObjectRegistry);
    function FindVariableIndex(const AName: string): Integer; // last definition, -1 if none
    function FindEndpointIndex(const AName: string): Integer; // first definition, -1 if none
    { dependency graph nodes: the variables first, then the endpoints }
    function NodeCount: Integer;
    function NodeOfEndpoint(AIndex: Integer): Integer;
    function OwnerNode(const AExpression: TLintExpression): Integer;
    function NodeLabel(ANode: Integer): string;
    function NodeRow(ANode: Integer): Integer;
    function NodeColumn(ANode: Integer): Integer;
    function NodeToken(ANode: Integer): string;
    property HttpFile: THttpFile read FFile;
    property Functions: THttpFunctionRegistry read FFunctions; // may be nil
    property Objects: TScriptObjectRegistry read FObjects;     // may be nil
    property Expressions: TLintExpressionArray read FExpressions;
  end;

  THttpLintRule = class
  public
    function Id: string; virtual; abstract;
    procedure Check(AContext: THttpLintContext; ADiagnostics: THttpParseErrorList); virtual; abstract;
  end;

  TDuplicateRequestNameRule = class(THttpLintRule)
  public
    function Id: string; override;
    procedure Check(AContext: THttpLintContext; ADiagnostics: THttpParseErrorList); override;
  end;

  TUnusedVariableRule = class(THttpLintRule)
  public
    function Id: string; override;
    procedure Check(AContext: THttpLintContext; ADiagnostics: THttpParseErrorList); override;
  end;

  TUnresolvedPlaceholderRule = class(THttpLintRule)
  private
    function IsKnownObject(AContext: THttpLintContext; const AInner: string): Boolean;
  public
    function Id: string; override;
    procedure Check(AContext: THttpLintContext; ADiagnostics: THttpParseErrorList); override;
  end;

  TCircularReferenceRule = class(THttpLintRule)
  private
    FContext: THttpLintContext;
    FDiagnostics: THttpParseErrorList;
    FEdges: array of array of Integer;
    FColors: array of Byte; // 0 = new, 1 = on the stack, 2 = done
    FStack: array of Integer;
    FReported: TStringList;
    procedure AddEdge(AFrom, ATo: Integer);
    procedure BuildGraph;
    procedure Visit(ANode: Integer);
    procedure ReportCycle(AStartNode: Integer);
  public
    function Id: string; override;
    procedure Check(AContext: THttpLintContext; ADiagnostics: THttpParseErrorList); override;
  end;

  THttpFileLinter = class
  private
    FRules: array of THttpLintRule;
    FFunctions: THttpFunctionRegistry;
    FObjects: TScriptObjectRegistry;
  public
    { the registries are not owned; pass the parser's Functions and Scripting }
    constructor Create(AFunctions: THttpFunctionRegistry = nil;
      AObjects: TScriptObjectRegistry = nil; AWithDefaultRules: Boolean = True);
    destructor Destroy; override;
    { takes ownership of ARule }
    procedure AddRule(ARule: THttpLintRule);
    function RuleCount: Integer;
    { appends the warnings to ADiagnostics and sorts the list by position }
    procedure Lint(AFile: THttpFile; ADiagnostics: THttpParseErrorList);
  end;

implementation

{ THttpLintContext }

constructor THttpLintContext.Create(AFile: THttpFile; AFunctions: THttpFunctionRegistry;
  AObjects: TScriptObjectRegistry);
begin
  inherited Create;
  FFile := AFile;
  FFunctions := AFunctions;
  FObjects := AObjects;
  Collect;
end;

procedure THttpLintContext.AddExpressions(const AText: string; ARow, AColumn: Integer;
  AKind: TLintOwnerKind; AIndex: Integer);
var
  I, CloseAt, Row, Col, Done: Integer;
  Item: TLintExpression;
begin
  Row := ARow;
  Col := AColumn;
  Done := 1; // first character not yet counted in Row/Col
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '{') and (I < Length(AText)) and (AText[I + 1] = '{') then
    begin
      CloseAt := PosEx('}}', AText, I + 2);
      if CloseAt = 0 then
        Exit; // unterminated: the parser reports it
      AdvancePosition(Row, Col, Copy(AText, Done, I - Done));
      Done := I;
      Item.Raw := Copy(AText, I, CloseAt + 2 - I);
      Item.Inner := Trim(Copy(AText, I + 2, CloseAt - I - 2));
      Item.Row := Row;
      Item.Column := Col;
      Item.OwnerKind := AKind;
      Item.OwnerIndex := AIndex;
      SetLength(FExpressions, Length(FExpressions) + 1);
      FExpressions[High(FExpressions)] := Item;
      I := CloseAt + 2;
    end
    else
      Inc(I);
  end;
end;

procedure THttpLintContext.Collect;
var
  I, J: Integer;
  V: TVariable;
  E: TEndpoint;
begin
  FExpressions := nil;
  for I := 0 to High(FFile.Variables) do
  begin
    V := FFile.Variables[I];
    AddExpressions(V.RawValue, V.Row, V.ValueColumn, okVariable, I);
  end;
  for I := 0 to High(FFile.Endpoints) do
  begin
    E := FFile.Endpoints[I];
    AddExpressions(E.RawUrl, E.Row, E.UrlColumn, okEndpoint, I);
    for J := 0 to High(E.RequestHeaders) do
      AddExpressions(E.RequestHeaders[J].RawValue, E.RequestHeaders[J].Row,
        E.RequestHeaders[J].ValueColumn, okEndpoint, I);
    if E.RawRequestBody <> '' then
      AddExpressions(E.RawRequestBody, E.BodyRow, 1, okEndpoint, I);
  end;
end;

function THttpLintContext.FindVariableIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := High(FFile.Variables) downto 0 do
    if FFile.Variables[I].Name = AName then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function THttpLintContext.FindEndpointIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FFile.Endpoints) do
    if FFile.Endpoints[I].Name = AName then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function THttpLintContext.NodeCount: Integer;
begin
  Result := Length(FFile.Variables) + Length(FFile.Endpoints);
end;

function THttpLintContext.NodeOfEndpoint(AIndex: Integer): Integer;
begin
  Result := Length(FFile.Variables) + AIndex;
end;

function THttpLintContext.OwnerNode(const AExpression: TLintExpression): Integer;
begin
  if AExpression.OwnerKind = okVariable then
    Result := AExpression.OwnerIndex
  else
    Result := NodeOfEndpoint(AExpression.OwnerIndex);
end;

function THttpLintContext.NodeLabel(ANode: Integer): string;
var
  E: TEndpoint;
begin
  if ANode < Length(FFile.Variables) then
    Result := '@' + FFile.Variables[ANode].Name
  else
  begin
    E := FFile.Endpoints[ANode - Length(FFile.Variables)];
    if E.Name <> '' then
      Result := 'request "' + E.Name + '"'
    else
      Result := 'request at line ' + IntToStr(E.Row);
  end;
end;

function THttpLintContext.NodeRow(ANode: Integer): Integer;
begin
  if ANode < Length(FFile.Variables) then
    Result := FFile.Variables[ANode].Row
  else
    Result := FFile.Endpoints[ANode - Length(FFile.Variables)].Row;
end;

function THttpLintContext.NodeColumn(ANode: Integer): Integer;
begin
  if ANode < Length(FFile.Variables) then
    Result := FFile.Variables[ANode].Column
  else
    Result := FFile.Endpoints[ANode - Length(FFile.Variables)].Column;
end;

function THttpLintContext.NodeToken(ANode: Integer): string;
begin
  if ANode < Length(FFile.Variables) then
    Result := '@' + FFile.Variables[ANode].Name
  else
    Result := FFile.Endpoints[ANode - Length(FFile.Variables)].Verb;
end;

{ TDuplicateRequestNameRule }

function TDuplicateRequestNameRule.Id: string;
begin
  Result := 'lint-duplicate-request';
end;

procedure TDuplicateRequestNameRule.Check(AContext: THttpLintContext;
  ADiagnostics: THttpParseErrorList);
var
  I, First: Integer;
  E: TEndpoint;
begin
  for I := 0 to High(AContext.HttpFile.Endpoints) do
  begin
    E := AContext.HttpFile.Endpoints[I];
    if E.Name = '' then
      Continue; // unnamed requests cannot clash
    First := AContext.FindEndpointIndex(E.Name);
    if First < I then
      ADiagnostics.Add(hsWarning, E.Row, E.Column,
        Format('Duplicate request name "%s" (first defined at line %d)',
          [E.Name, AContext.HttpFile.Endpoints[First].Row]), E.Verb, Id);
  end;
end;

{ TUnusedVariableRule }

function TUnusedVariableRule.Id: string;
begin
  Result := 'lint-unused-variable';
end;

procedure TUnusedVariableRule.Check(AContext: THttpLintContext;
  ADiagnostics: THttpParseErrorList);
var
  Used: TStringList;
  I: Integer;
  Item: TLintExpression;
  V: TVariable;
begin
  Used := TStringList.Create;
  try
    Used.CaseSensitive := True;
    for I := 0 to High(AContext.Expressions) do
    begin
      Item := AContext.Expressions[I];
      if (Item.Inner = '') or (Item.Inner[1] = '$') then
        Continue;
      if AContext.FindVariableIndex(Item.Inner) < 0 then
        Continue;
      if (Item.OwnerKind = okVariable) and
         (AContext.HttpFile.Variables[Item.OwnerIndex].Name = Item.Inner) then
        Continue; // a variable that only refers to itself is not used
      if Used.IndexOf(Item.Inner) < 0 then
        Used.Add(Item.Inner);
    end;
    for I := 0 to High(AContext.HttpFile.Variables) do
    begin
      V := AContext.HttpFile.Variables[I];
      if Used.IndexOf(V.Name) < 0 then
        ADiagnostics.Add(hsWarning, V.Row, V.Column,
          Format('Variable "%s" is never used', [V.Name]), '@' + V.Name, Id);
    end;
  finally
    Used.Free;
  end;
end;

{ TUnresolvedPlaceholderRule }

function TUnresolvedPlaceholderRule.Id: string;
begin
  Result := 'lint-unresolved-placeholder';
end;

function TUnresolvedPlaceholderRule.IsKnownObject(AContext: THttpLintContext;
  const AInner: string): Boolean;
var
  Dot: Integer;
  Name: string;
begin
  Result := False;
  if AContext.Objects = nil then
    Exit;
  Dot := Pos('.', AInner);
  if Dot = 0 then
    Name := AInner
  else
    Name := Copy(AInner, 1, Dot - 1);
  Result := AContext.Objects.IsRegistered(Name);
end;

procedure TUnresolvedPlaceholderRule.Check(AContext: THttpLintContext;
  ADiagnostics: THttpParseErrorList);
var
  I, Stop: Integer;
  Item: TLintExpression;
  Ref: TRequestReference;
  Msg, FunctionName: string;
begin
  for I := 0 to High(AContext.Expressions) do
  begin
    Item := AContext.Expressions[I];
    if Item.Inner = '' then
      Continue;
    if Item.Inner[1] = '$' then
    begin
      if AContext.Functions = nil then
        Continue;
      Stop := 2;
      while (Stop <= Length(Item.Inner)) and (Item.Inner[Stop] <> ' ') and
            (Item.Inner[Stop] <> #9) do
        Inc(Stop);
      FunctionName := Copy(Item.Inner, 2, Stop - 2);
      if not AContext.Functions.IsRegistered(FunctionName) then
        ADiagnostics.Add(hsWarning, Item.Row, Item.Column,
          Format('Unknown function "$%s"', [FunctionName]), Item.Raw, Id);
      Continue;
    end;
    if AContext.FindVariableIndex(Item.Inner) >= 0 then
      Continue;
    case MatchRequestReference(AContext.HttpFile, Item.Inner, Ref, Msg) of
      rmInvalid:
        ADiagnostics.Add(hsWarning, Item.Row, Item.Column, Msg, Item.Raw, Id);
      rmNotAReference:
        if not IsKnownObject(AContext, Item.Inner) then
          ADiagnostics.Add(hsWarning, Item.Row, Item.Column,
            Format('Unresolved placeholder "%s": no such variable, request or object',
              [Item.Inner]), Item.Raw, Id);
    end;
  end;
end;

{ TCircularReferenceRule }

function TCircularReferenceRule.Id: string;
begin
  Result := 'lint-circular-reference';
end;

procedure TCircularReferenceRule.AddEdge(AFrom, ATo: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FEdges[AFrom]) do
    if FEdges[AFrom][I] = ATo then
      Exit;
  SetLength(FEdges[AFrom], Length(FEdges[AFrom]) + 1);
  FEdges[AFrom][High(FEdges[AFrom])] := ATo;
end;

procedure TCircularReferenceRule.BuildGraph;
var
  I, Target: Integer;
  Item: TLintExpression;
  Ref: TRequestReference;
  Msg: string;
begin
  SetLength(FEdges, FContext.NodeCount);
  SetLength(FColors, FContext.NodeCount);
  for I := 0 to High(FColors) do
    FColors[I] := 0;
  for I := 0 to High(FContext.Expressions) do
  begin
    Item := FContext.Expressions[I];
    if (Item.Inner = '') or (Item.Inner[1] = '$') then
      Continue;
    Target := FContext.FindVariableIndex(Item.Inner);
    if Target < 0 then
    begin
      if MatchRequestReference(FContext.HttpFile, Item.Inner, Ref, Msg) <> rmValid then
        Continue;
      Target := FContext.FindEndpointIndex(Ref.RequestName);
      if Target < 0 then
        Continue;
      Target := FContext.NodeOfEndpoint(Target);
    end;
    AddEdge(FContext.OwnerNode(Item), Target);
  end;
end;

procedure TCircularReferenceRule.ReportCycle(AStartNode: Integer);
var
  StartPos, I, J, Tmp, Count, Best: Integer;
  Path, Sorted: array of Integer;
  Key, PathText: string;
begin
  StartPos := 0;
  while FStack[StartPos] <> AStartNode do
    Inc(StartPos);
  Count := Length(FStack) - StartPos;
  SetLength(Path, Count);
  SetLength(Sorted, Count);
  for I := 0 to Count - 1 do
  begin
    Path[I] := FStack[StartPos + I];  // search order, for the message
    Sorted[I] := Path[I];
  end;

  // the same set of nodes is one cycle, whichever node the search entered by
  for I := 0 to Count - 1 do
    for J := I + 1 to Count - 1 do
      if Sorted[J] < Sorted[I] then
      begin
        Tmp := Sorted[I];
        Sorted[I] := Sorted[J];
        Sorted[J] := Tmp;
      end;
  Key := '';
  for I := 0 to Count - 1 do
    Key := Key + IntToStr(Sorted[I]) + ',';
  if FReported.IndexOf(Key) >= 0 then
    Exit;
  FReported.Add(Key);

  PathText := '';
  for I := 0 to Count - 1 do
    PathText := PathText + FContext.NodeLabel(Path[I]) + ' -> ';
  PathText := PathText + FContext.NodeLabel(Path[0]);

  Best := Path[0]; // reported where the cycle starts in the file
  for I := 1 to Count - 1 do
    if (FContext.NodeRow(Path[I]) < FContext.NodeRow(Best)) or
       ((FContext.NodeRow(Path[I]) = FContext.NodeRow(Best)) and
        (FContext.NodeColumn(Path[I]) < FContext.NodeColumn(Best))) then
      Best := Path[I];
  FDiagnostics.Add(hsWarning, FContext.NodeRow(Best), FContext.NodeColumn(Best),
    'Circular reference: ' + PathText, FContext.NodeToken(Best), Id);
end;

procedure TCircularReferenceRule.Visit(ANode: Integer);
var
  I: Integer;
begin
  FColors[ANode] := 1;
  SetLength(FStack, Length(FStack) + 1);
  FStack[High(FStack)] := ANode;
  for I := 0 to High(FEdges[ANode]) do
    if FColors[FEdges[ANode][I]] = 0 then
      Visit(FEdges[ANode][I])
    else if FColors[FEdges[ANode][I]] = 1 then
      ReportCycle(FEdges[ANode][I]);
  SetLength(FStack, Length(FStack) - 1);
  FColors[ANode] := 2;
end;

procedure TCircularReferenceRule.Check(AContext: THttpLintContext;
  ADiagnostics: THttpParseErrorList);
var
  I: Integer;
begin
  FContext := AContext;
  FDiagnostics := ADiagnostics;
  FEdges := nil;
  FColors := nil;
  FStack := nil;
  FReported := TStringList.Create;
  try
    BuildGraph;
    for I := 0 to High(FColors) do
      if FColors[I] = 0 then
        Visit(I);
  finally
    FReported.Free;
  end;
end;

{ THttpFileLinter }

constructor THttpFileLinter.Create(AFunctions: THttpFunctionRegistry;
  AObjects: TScriptObjectRegistry; AWithDefaultRules: Boolean);
begin
  inherited Create;
  FFunctions := AFunctions;
  FObjects := AObjects;
  if AWithDefaultRules then
  begin
    AddRule(TDuplicateRequestNameRule.Create);
    AddRule(TUnusedVariableRule.Create);
    AddRule(TUnresolvedPlaceholderRule.Create);
    AddRule(TCircularReferenceRule.Create);
  end;
end;

destructor THttpFileLinter.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FRules) do
    FRules[I].Free;
  inherited Destroy;
end;

procedure THttpFileLinter.AddRule(ARule: THttpLintRule);
begin
  SetLength(FRules, Length(FRules) + 1);
  FRules[High(FRules)] := ARule;
end;

function THttpFileLinter.RuleCount: Integer;
begin
  Result := Length(FRules);
end;

procedure THttpFileLinter.Lint(AFile: THttpFile; ADiagnostics: THttpParseErrorList);
var
  Context: THttpLintContext;
  I: Integer;
begin
  Context := THttpLintContext.Create(AFile, FFunctions, FObjects);
  try
    for I := 0 to High(FRules) do
      FRules[I].Check(Context, ADiagnostics);
  finally
    Context.Free;
  end;
  ADiagnostics.SortByPosition;
end;

end.
