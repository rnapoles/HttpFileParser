(* HttpFileInterpolator - expands double-brace expressions in text.

  Resolution order for an expression:
  1. the name of a file variable ........... replaced by its resolved value
  2. $function arg ... ..................... registered function is called;
                                             quotes group arguments with blanks
  3. request.(request|response).(body|headers).selector
                                             see HttpFileReferences. Request
                                             scope is read from the file itself,
                                             response scope from the response
                                             store; a response that was not
                                             stored yet leaves the text as is
  4. object.Property[.Property] ............ registered object (RTTI)
  Anything else (request or environment variables of the HTTP client) is left
  untouched. Problems are added to the error list and leave the expression
  as written. Replacement is single pass: replaced text is never rescanned. *)
unit HttpFileInterpolator;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, StrUtils, HttpFileAST, HttpFileFunctions, HttpFileResponses,
  HttpFileScripting, HttpFileReferences, HttpFileSelectors;

type
  THttpInterpolator = class
  private
    FFile: THttpFile;
    FFunctions: THttpFunctionRegistry;
    FContext: THttpFunctionContext;
    FErrors: THttpParseErrorList;
    FResponses: THttpResponseStore; // may be nil
    FObjects: TScriptObjectRegistry; // may be nil
    FVariableState: array of Byte; // 0 = pending, 1 = resolving, 2 = done
    FEndpointState: array of Byte;
    function FindVariableIndex(const AName: string): Integer;
    function FindEndpointIndex(const AName: string): Integer;
    function ResolveVariable(AIndex: Integer): string;
    procedure ResolveEndpoint(AIndex: Integer);
    function EvaluateFunction(const AInner, ARaw: string; ARow, ACol: Integer): string;
    function EvaluateReference(const AInner, ARaw: string; ARow, ACol: Integer): string;
    function SelectFromResponse(const ARef: TRequestReference; out AValue: string): Boolean;
    function SelectFromRequest(const ARef: TRequestReference): string;
    procedure ParseCall(const AInner: string; out AName: string; out AArgs: THttpArgs);
    procedure Report(const AText: string; AIndex, ARow, ACol: Integer;
      const AMessage, AToken, ARule: string);
  public
    constructor Create(AFile: THttpFile; AFunctions: THttpFunctionRegistry;
      AContext: THttpFunctionContext; AErrors: THttpParseErrorList;
      AResponses: THttpResponseStore; AObjects: TScriptObjectRegistry);
    { ARow/ACol are the coordinates of the first character of AText. }
    function Expand(const AText: string; ARow, ACol: Integer): string;
    { Resolves every variable, then every endpoint. }
    procedure Apply;
  end;

implementation

function IsWs(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

constructor THttpInterpolator.Create(AFile: THttpFile; AFunctions: THttpFunctionRegistry;
  AContext: THttpFunctionContext; AErrors: THttpParseErrorList;
  AResponses: THttpResponseStore; AObjects: TScriptObjectRegistry);
var
  I: Integer;
begin
  inherited Create;
  FFile := AFile;
  FFunctions := AFunctions;
  FContext := AContext;
  FErrors := AErrors;
  FResponses := AResponses;
  FObjects := AObjects;
  SetLength(FVariableState, Length(AFile.Variables));
  for I := 0 to High(FVariableState) do
    FVariableState[I] := 0;
  SetLength(FEndpointState, Length(AFile.Endpoints));
  for I := 0 to High(FEndpointState) do
    FEndpointState[I] := 0;
end;

procedure THttpInterpolator.Report(const AText: string; AIndex, ARow, ACol: Integer;
  const AMessage, AToken, ARule: string);
var
  K, R, C: Integer;
begin
  R := ARow;
  C := ACol;
  for K := 1 to AIndex - 1 do
    if AText[K] = #10 then
    begin
      Inc(R);
      C := 1;
    end
    else
      Inc(C);
  FErrors.Add(R, C, AMessage, AToken, ARule);
end;

function THttpInterpolator.FindVariableIndex(const AName: string): Integer;
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

function THttpInterpolator.FindEndpointIndex(const AName: string): Integer;
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

function THttpInterpolator.ResolveVariable(AIndex: Integer): string;
var
  V: TVariable;
begin
  V := FFile.Variables[AIndex];
  case FVariableState[AIndex] of
    2: Result := V.Value;
    1:
      begin
        FErrors.Add(V.Row, V.Column, 'Circular variable reference: ' + V.Name,
          '{{' + V.Name + '}}', 'VariableReference');
        Result := '{{' + V.Name + '}}';
      end;
  else
    begin
      FVariableState[AIndex] := 1;
      V.Value := Expand(V.RawValue, V.Row, V.ValueColumn);
      FVariableState[AIndex] := 2;
      Result := V.Value;
    end;
  end;
end;

procedure THttpInterpolator.ResolveEndpoint(AIndex: Integer);
var
  E: TEndpoint;
  J: Integer;
  H: TRequestHeader;
begin
  FEndpointState[AIndex] := 1;
  E := FFile.Endpoints[AIndex];
  E.Url := Expand(E.RawUrl, E.Row, E.UrlColumn);
  for J := 0 to High(E.RequestHeaders) do
  begin
    H := E.RequestHeaders[J];
    H.Value := Expand(H.RawValue, H.Row, H.ValueColumn);
  end;
  if E.BodyFilePath <> '' then
    E.BodyFilePath := Expand(E.BodyFilePath, E.BodyRow, E.BodyFileColumn)
  else
    E.RequestBody := Expand(E.RawRequestBody, E.BodyRow, 1);
  FEndpointState[AIndex] := 2;
end;

procedure THttpInterpolator.ParseCall(const AInner: string; out AName: string;
  out AArgs: THttpArgs);
var
  I, L, Start: Integer;
  Q: Char;
begin
  L := Length(AInner);
  I := 2; // skip '$'
  Start := I;
  while (I <= L) and not IsWs(AInner[I]) do
    Inc(I);
  AName := Copy(AInner, Start, I - Start);
  SetLength(AArgs, 0);
  while True do
  begin
    while (I <= L) and IsWs(AInner[I]) do
      Inc(I);
    if I > L then
      Break;
    if (AInner[I] = '"') or (AInner[I] = '''') then
    begin
      Q := AInner[I];
      Inc(I);
      Start := I;
      while (I <= L) and (AInner[I] <> Q) do
        Inc(I);
      if I > L then
        raise EHttpFunctionError.Create('Unterminated quoted argument');
      SetLength(AArgs, Length(AArgs) + 1);
      AArgs[High(AArgs)] := Copy(AInner, Start, I - Start);
      Inc(I);
    end
    else
    begin
      Start := I;
      while (I <= L) and not IsWs(AInner[I]) do
        Inc(I);
      SetLength(AArgs, Length(AArgs) + 1);
      AArgs[High(AArgs)] := Copy(AInner, Start, I - Start);
    end;
  end;
end;

function THttpInterpolator.EvaluateFunction(const AInner, ARaw: string;
  ARow, ACol: Integer): string;
var
  Name: string;
  Args: THttpArgs;
begin
  try
    ParseCall(AInner, Name, Args);
    Result := FFunctions.Execute(Name, Args, FContext);
  except
    on E: Exception do
    begin
      FErrors.Add(ARow, ACol, E.Message, ARaw, 'FunctionCall');
      Result := ARaw;
    end;
  end;
end;

function THttpInterpolator.SelectFromResponse(const ARef: TRequestReference;
  out AValue: string): Boolean;
var
  Response: THttpResponse;
begin
  AValue := '';
  Response := nil;
  if FResponses <> nil then
    Response := FResponses.Find(ARef.RequestName);
  Result := Response <> nil;
  if not Result then
    Exit; // not executed yet: the expression stays as written
  case ARef.Part of
    rpBody:
      AValue := SelectFromBody(Response.Body, ARef.Selector);
    rpHeaders:
      if not Response.FindHeader(ARef.Selector, AValue) then
        raise EHttpSelectorError.CreateFmt('Header "%s" not found in the response of "%s"',
          [ARef.Selector, ARef.RequestName]);
  end;
end;

function THttpInterpolator.SelectFromRequest(const ARef: TRequestReference): string;
var
  Idx: Integer;
  Target: TEndpoint;
  Header: TRequestHeader;
begin
  Idx := FindEndpointIndex(ARef.RequestName);
  if Idx < 0 then
    raise EHttpSelectorError.CreateFmt('Unknown request "%s"', [ARef.RequestName]);
  if FEndpointState[Idx] = 1 then
    raise EHttpSelectorError.CreateFmt('Circular reference to request "%s"', [ARef.RequestName]);
  if FEndpointState[Idx] = 0 then
    ResolveEndpoint(Idx);
  Target := FFile.Endpoints[Idx];
  case ARef.Part of
    rpBody:
      begin
        if Target.BodyFilePath <> '' then
          raise EHttpSelectorError.CreateFmt('The body of "%s" is a file reference', [ARef.RequestName]);
        Result := SelectFromBody(Target.RequestBody, ARef.Selector);
      end;
    rpHeaders:
      begin
        Header := Target.FindRequestHeader(ARef.Selector);
        if Header = nil then
          raise EHttpSelectorError.CreateFmt('Header "%s" not found in request "%s"',
            [ARef.Selector, ARef.RequestName]);
        Result := Header.Value;
      end;
  end;
end;

function THttpInterpolator.EvaluateReference(const AInner, ARaw: string;
  ARow, ACol: Integer): string;
var
  Ref: TRequestReference;
  Msg, Value: string;
begin
  Result := ARaw;
  case MatchRequestReference(FFile, AInner, Ref, Msg) of
    rmInvalid:
      FErrors.Add(ARow, ACol, Msg, ARaw, 'RequestReference');
    rmValid:
      try
        if Ref.Scope = rsResponse then
        begin
          if SelectFromResponse(Ref, Value) then
            Result := Value;
        end
        else
          Result := SelectFromRequest(Ref);
      except
        on E: Exception do
        begin
          FErrors.Add(ARow, ACol, E.Message, ARaw, 'RequestReference');
          Result := ARaw;
        end;
      end;
  else
    if FObjects <> nil then
      try
        if FObjects.TryEvaluate(AInner, Value) then
          Result := Value;
      except
        on E: EScriptError do
          FErrors.Add(ARow, ACol, E.Message, ARaw, 'ScriptObject');
      end;
  end;
end;

function THttpInterpolator.Expand(const AText: string; ARow, ACol: Integer): string;
var
  I, RunStart, CloseAt, Idx, R, C, K: Integer;
  Inner, Raw: string;
begin
  Result := '';
  I := 1;
  RunStart := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '{') and (I < Length(AText)) and (AText[I + 1] = '{') then
    begin
      Result := Result + Copy(AText, RunStart, I - RunStart);
      CloseAt := PosEx('}}', AText, I + 2);
      if CloseAt = 0 then
      begin
        Report(AText, I, ARow, ACol, 'Unterminated {{ expression', Copy(AText, I, 20),
          'Expression');
        Result := Result + Copy(AText, I, MaxInt);
        Exit;
      end;
      Raw := Copy(AText, I, CloseAt + 2 - I);
      Inner := Trim(Copy(AText, I + 2, CloseAt - I - 2));
      // coordinates of the opening braces
      R := ARow;
      C := ACol;
      for K := 1 to I - 1 do
        if AText[K] = #10 then
        begin
          Inc(R);
          C := 1;
        end
        else
          Inc(C);
      if Inner = '' then
        Result := Result + Raw
      else if Inner[1] = '$' then
        Result := Result + EvaluateFunction(Inner, Raw, R, C)
      else
      begin
        Idx := FindVariableIndex(Inner);
        if Idx >= 0 then
          Result := Result + ResolveVariable(Idx)
        else
          Result := Result + EvaluateReference(Inner, Raw, R, C);
      end;
      I := CloseAt + 2;
      RunStart := I;
    end
    else
      Inc(I);
  end;
  Result := Result + Copy(AText, RunStart, MaxInt);
end;

procedure THttpInterpolator.Apply;
var
  I: Integer;
begin
  for I := 0 to High(FVariableState) do
    ResolveVariable(I);
  for I := 0 to High(FEndpointState) do
    if FEndpointState[I] = 0 then
      ResolveEndpoint(I);
end;

end.
