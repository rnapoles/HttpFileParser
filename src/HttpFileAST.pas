{ HttpFileAST - structural nodes produced by the HTTP file parser.
  Dual-compiler: Delphi 12+ and Free Pascal 3.2.2+ (no generics, no anonymous methods). }
unit HttpFileAST;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

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
    ResponseBody: string;     // filled from the response store (name must match)
    ResponseStatusCode: Integer; // 0 = no stored response
    ResponseStatusText: string;
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

  THttpSeverity = (hsError, hsWarning, hsInfo);

  THttpParseError = record
    Severity: THttpSeverity;
    Row: Integer;       // start, 1-based
    Column: Integer;
    EndRow: Integer;    // end, 1-based, exclusive column (zero-width: equals the start)
    EndColumn: Integer;
    Message: string;
    Token: string;      // offending text
    Rule: string;       // production rule or check that reported it
  end;

  THttpParseErrorList = class
  private
    FItems: array of THttpParseError;
    FCount: Integer;
    function GetItem(AIndex: Integer): THttpParseError;
    function GetErrorCount: Integer;
    function GetWarningCount: Integer;
    function GetInfoCount: Integer;
  public
    { error; the range ends after AToken }
    procedure Add(ARow, AColumn: Integer; const AMessage, AToken, ARule: string); overload;
    { the range ends after AToken, which may span several lines }
    procedure Add(ASeverity: THttpSeverity; ARow, AColumn: Integer;
      const AMessage, AToken, ARule: string); overload;
    procedure AddRange(ASeverity: THttpSeverity; ARow, AColumn, AEndRow, AEndColumn: Integer;
      const AMessage, AToken, ARule: string);
    procedure Clear;
    procedure SortByPosition;
    function CountOf(ASeverity: THttpSeverity): Integer;
    function HasErrors: Boolean;
    property Count: Integer read FCount;      // every entry, whatever its severity
    property ErrorCount: Integer read GetErrorCount;
    property WarningCount: Integer read GetWarningCount;
    property InfoCount: Integer read GetInfoCount;
    property Items[AIndex: Integer]: THttpParseError read GetItem; default;
  end;

  EHttpFileParseException = class(Exception)
  public
    Row: Integer;
    Column: Integer;
    Token: string;
    Rule: string;
    EndRow: Integer;
    EndColumn: Integer;
    constructor CreateAt(const AMessage: string; ARow, AColumn: Integer;
      const AToken, ARule: string);
  end;

function FormatParseError(const AError: THttpParseError): string;
function SeverityName(ASeverity: THttpSeverity): string;
{ moves a position over AText (line breaks start a new row at column 1) }
procedure AdvancePosition(var ARow, AColumn: Integer; const AText: string);

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

procedure THttpParseErrorList.AddRange(ASeverity: THttpSeverity;
  ARow, AColumn, AEndRow, AEndColumn: Integer; const AMessage, AToken, ARule: string);
begin
  if FCount = Length(FItems) then
    SetLength(FItems, FCount * 2 + 8);
  FItems[FCount].Severity := ASeverity;
  FItems[FCount].Row := ARow;
  FItems[FCount].Column := AColumn;
  FItems[FCount].EndRow := AEndRow;
  FItems[FCount].EndColumn := AEndColumn;
  FItems[FCount].Message := AMessage;
  FItems[FCount].Token := AToken;
  FItems[FCount].Rule := ARule;
  Inc(FCount);
end;

procedure THttpParseErrorList.Add(ASeverity: THttpSeverity; ARow, AColumn: Integer;
  const AMessage, AToken, ARule: string);
var
  EndRow, EndColumn: Integer;
begin
  EndRow := ARow;
  EndColumn := AColumn;
  AdvancePosition(EndRow, EndColumn, AToken);
  AddRange(ASeverity, ARow, AColumn, EndRow, EndColumn, AMessage, AToken, ARule);
end;

procedure THttpParseErrorList.Add(ARow, AColumn: Integer;
  const AMessage, AToken, ARule: string);
begin
  Add(hsError, ARow, AColumn, AMessage, AToken, ARule);
end;

function THttpParseErrorList.CountOf(ASeverity: THttpSeverity): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FCount - 1 do
    if FItems[I].Severity = ASeverity then
      Inc(Result);
end;

function THttpParseErrorList.GetErrorCount: Integer;
begin
  Result := CountOf(hsError);
end;

function THttpParseErrorList.GetWarningCount: Integer;
begin
  Result := CountOf(hsWarning);
end;

function THttpParseErrorList.GetInfoCount: Integer;
begin
  Result := CountOf(hsInfo);
end;

function THttpParseErrorList.HasErrors: Boolean;
begin
  Result := CountOf(hsError) > 0;
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
  EndRow := ARow;
  EndColumn := AColumn;
  AdvancePosition(EndRow, EndColumn, AToken);
end;

function SeverityName(ASeverity: THttpSeverity): string;
begin
  case ASeverity of
    hsError: Result := 'error';
    hsWarning: Result := 'warning';
  else
    Result := 'info';
  end;
end;

procedure AdvancePosition(var ARow, AColumn: Integer; const AText: string);
var
  I: Integer;
begin
  I := 1;
  while I <= Length(AText) do
  begin
    if AText[I] = #13 then
    begin
      if (I < Length(AText)) and (AText[I + 1] = #10) then
        Inc(I);
      Inc(ARow);
      AColumn := 1;
    end
    else if AText[I] = #10 then
    begin
      Inc(ARow);
      AColumn := 1;
    end
    else
      Inc(AColumn);
    Inc(I);
  end;
end;

function FormatParseError(const AError: THttpParseError): string;
begin
  Result := Format('%s: %s (%d:%d-%d:%d, rule %s, near "%s")',
    [SeverityName(AError.Severity), AError.Message, AError.Row, AError.Column,
     AError.EndRow, AError.EndColumn, AError.Rule, AError.Token]);
end;

end.
