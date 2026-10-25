{ HttpFileAST - structural nodes produced by the HTTP file parser.
  Dual-compiler: Delphi 12+ and Free Pascal 3.2.2+ (no generics, no anonymous methods). }
unit HttpFileAST;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils;

type
  THttpNode = class
  public
    Row: Integer;     // 1-based
    Column: Integer;  // 1-based
  end;

  THttpHeader = class(THttpNode)
  public
    Name: string;
    Value: string;      // after variable / function replacement
    RawValue: string;   // as written in the file
    ValueColumn: Integer;
  end;

  TRequestHeader = class(THttpHeader);
  TResponseHeader = class(THttpHeader);

  TRequestHeaderArray = array of TRequestHeader;
  TResponseHeaderArray = array of TResponseHeader;

  TVariable = class(THttpNode)
  public
    Name: string;
    Value: string;      // variables, functions, references and objects replaced; unresolved response references stay raw
    RawValue: string;
    ValueColumn: Integer;
  end;

  TVariableArray = array of TVariable;

  TEndpoint = class(THttpNode)
  private
    FRequestHeaders: TRequestHeaderArray;
    FResponseHeaders: TResponseHeaderArray;
  public
    Name: string;
    Verb: string;
    Url: string;
    HttpRevision: string;     // default 'HTTP/1.1'
    RawUrl: string;
    RequestBody: string;      // empty when the body is a file reference
    RawRequestBody: string;
    ResponseBody: string;     // never filled by the parser
    BodyFilePath: string;     // set for "< path" bodies
    UrlColumn: Integer;
    BodyRow: Integer;
    BodyFileColumn: Integer;
    constructor Create;
    destructor Destroy; override;
    function AddRequestHeader: TRequestHeader;
    function AddResponseHeader: TResponseHeader;
    function FindRequestHeader(const AName: string): TRequestHeader;
    property RequestHeaders: TRequestHeaderArray read FRequestHeaders;
    property ResponseHeaders: TResponseHeaderArray read FResponseHeaders;
  end;

  TEndpointArray = array of TEndpoint;

  THttpFile = class
  private
    FVariables: TVariableArray;
    FEndpoints: TEndpointArray;
  public
    destructor Destroy; override;
    function AddVariable: TVariable;
    procedure AddEndpoint(AEndpoint: TEndpoint); // takes ownership
    function FindVariable(const AName: string): TVariable; // last definition wins
    function FindEndpoint(const AName: string): TEndpoint;
    property Variables: TVariableArray read FVariables;
    property Endpoints: TEndpointArray read FEndpoints;
  end;

  THttpParseError = record
    Row: Integer;
    Column: Integer;
    Message: string;
    Token: string;   // offending text
    Rule: string;    // production rule that failed
  end;

  THttpParseErrorList = class
  private
    FItems: array of THttpParseError;
    FCount: Integer;
    function GetItem(AIndex: Integer): THttpParseError;
  public
    procedure Add(ARow, AColumn: Integer; const AMessage, AToken, ARule: string);
    procedure Clear;
    procedure SortByPosition;
    property Count: Integer read FCount;
    property Items[AIndex: Integer]: THttpParseError read GetItem; default;
  end;

  EHttpFileParseException = class(Exception)
  public
    Row: Integer;
    Column: Integer;
    Token: string;
    Rule: string;
    constructor CreateAt(const AMessage: string; ARow, AColumn: Integer;
      const AToken, ARule: string);
  end;

function FormatParseError(const AError: THttpParseError): string;

implementation

{ TEndpoint }

constructor TEndpoint.Create;
begin
  inherited Create;
  HttpRevision := 'HTTP/1.1';
end;

destructor TEndpoint.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FRequestHeaders) do
    FRequestHeaders[I].Free;
  for I := 0 to High(FResponseHeaders) do
    FResponseHeaders[I].Free;
  inherited Destroy;
end;

function TEndpoint.AddRequestHeader: TRequestHeader;
begin
  Result := TRequestHeader.Create;
  SetLength(FRequestHeaders, Length(FRequestHeaders) + 1);
  FRequestHeaders[High(FRequestHeaders)] := Result;
end;

function TEndpoint.AddResponseHeader: TResponseHeader;
begin
  Result := TResponseHeader.Create;
  SetLength(FResponseHeaders, Length(FResponseHeaders) + 1);
  FResponseHeaders[High(FResponseHeaders)] := Result;
end;

function TEndpoint.FindRequestHeader(const AName: string): TRequestHeader;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FRequestHeaders) do
    if SameText(FRequestHeaders[I].Name, AName) then
    begin
      Result := FRequestHeaders[I];
      Exit;
    end;
end;

{ THttpFile }

destructor THttpFile.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FVariables) do
    FVariables[I].Free;
  for I := 0 to High(FEndpoints) do
    FEndpoints[I].Free;
  inherited Destroy;
end;

function THttpFile.AddVariable: TVariable;
begin
  Result := TVariable.Create;
  SetLength(FVariables, Length(FVariables) + 1);
  FVariables[High(FVariables)] := Result;
end;

procedure THttpFile.AddEndpoint(AEndpoint: TEndpoint);
begin
  SetLength(FEndpoints, Length(FEndpoints) + 1);
  FEndpoints[High(FEndpoints)] := AEndpoint;
end;

function THttpFile.FindVariable(const AName: string): TVariable;
var
  I: Integer;
begin
  Result := nil;
  for I := High(FVariables) downto 0 do
    if FVariables[I].Name = AName then
    begin
      Result := FVariables[I];
      Exit;
    end;
end;

function THttpFile.FindEndpoint(const AName: string): TEndpoint;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(FEndpoints) do
    if FEndpoints[I].Name = AName then
    begin
      Result := FEndpoints[I];
      Exit;
    end;
end;

{ THttpParseErrorList }

function THttpParseErrorList.GetItem(AIndex: Integer): THttpParseError;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise ERangeError.CreateFmt('Parse error index %d out of range', [AIndex]);
  Result := FItems[AIndex];
end;

procedure THttpParseErrorList.Add(ARow, AColumn: Integer;
  const AMessage, AToken, ARule: string);
begin
  if FCount = Length(FItems) then
    SetLength(FItems, FCount * 2 + 8);
  FItems[FCount].Row := ARow;
  FItems[FCount].Column := AColumn;
  FItems[FCount].Message := AMessage;
  FItems[FCount].Token := AToken;
  FItems[FCount].Rule := ARule;
  Inc(FCount);
end;

procedure THttpParseErrorList.Clear;
begin
  FCount := 0;
  SetLength(FItems, 0);
end;

procedure THttpParseErrorList.SortByPosition;
var
  I, J: Integer;
  Tmp: THttpParseError;
begin
  // stable insertion sort (error lists are short)
  for I := 1 to FCount - 1 do
  begin
    Tmp := FItems[I];
    J := I - 1;
    while (J >= 0) and
      ((FItems[J].Row > Tmp.Row) or
       ((FItems[J].Row = Tmp.Row) and (FItems[J].Column > Tmp.Column))) do
    begin
      FItems[J + 1] := FItems[J];
      Dec(J);
    end;
    FItems[J + 1] := Tmp;
  end;
end;

{ EHttpFileParseException }

constructor EHttpFileParseException.CreateAt(const AMessage: string;
  ARow, AColumn: Integer; const AToken, ARule: string);
begin
  inherited Create(AMessage);
  Row := ARow;
  Column := AColumn;
  Token := AToken;
  Rule := ARule;
end;

function FormatParseError(const AError: THttpParseError): string;
begin
  Result := Format('%s (line %d, column %d, rule %s, near "%s")',
    [AError.Message, AError.Row, AError.Column, AError.Rule, AError.Token]);
end;

end.
