(* HttpFileParser - recursive descent parser for .http files.

  Grammar (one ParseXxx method per non-terminal; lines are the terminals):

    HttpFile       = { Item } EOF ;
    Item           = Blank | Comment | Separator | MetaName | VariableDecl
                   | Endpoint | Script[error] ;
    Separator      = "###" [ Title ] ;                 -- Title = default name
    MetaName       = ("#" | "//") "@name" [ "=" ] Name ;
    VariableDecl   = "@" Ident "=" Value ;
    Endpoint       = RequestLine { QueryContinuation } Headers [ Body ] ;
    RequestLine    = [ Verb ] Url [ "HTTP/" Version ] ;
    Headers        = { HeaderLine | Comment | Script[error] } [ Blank ] ;
    HeaderLine     = Name ":" Value ;
    Body           = { BodyLine } | FileRef ;
    FileRef        = "<" Path ;

  A body ends at: "###", "# @name", a variable declaration, EOF, or a request
  line that follows a blank/comment line. Trailing blank/comment lines and
  leading blank lines are not part of the body. Line breaks inside bodies are
  normalised to LF.

  Scripts ("< {% ... %}", "> {% ... %}") are NOT supported: they are reported
  as errors and skipped. *)
unit HttpFileParser;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, HttpFileLexer, HttpFileAST, HttpFileFunctions,
  HttpFileInterpolator;

type
  THttpFileParser = class
  private
    FInput: string;
    FLexer: THttpFileLexer;
    FToken: THttpToken;
    FTokenIndex: Integer;
    FFile: THttpFile;
    FErrors: THttpParseErrorList;
    FFunctions: THttpFunctionRegistry;
    FContext: THttpFunctionContext;
    FParsed: Boolean;
    FPendingName: string;
    FPendingTitle: string;
    function GetHttpFile: THttpFile;
    function GetErrors: THttpParseErrorList;
    function GetBaseDirectory: string;
    procedure SetBaseDirectory(const AValue: string);
    { token handling }
    procedure Advance;
    procedure AddError(ARow, ACol: Integer; const AMessage, AToken, ARule: string);
    procedure Fail(const AMessage, ARule: string);
    function DescribeToken: string;
    procedure Synchronize(AStartIndex: Integer);
    { grammar }
    procedure ParseHttpFile;
    procedure ParseItem;
    procedure ParseSeparator;
    procedure ParseMetaName;
    function ParseVariableDecl: TVariable;
    function ParseEndpoint: TEndpoint;
    procedure ParseRequestLine(AEndpoint: TEndpoint);
    procedure ParseQueryContinuations(AEndpoint: TEndpoint);
    function ParseHeaders(AEndpoint: TEndpoint): Boolean; // True = body follows
    function ParseHeader(AEndpoint: TEndpoint): TRequestHeader;
    procedure ParseBody(AEndpoint: TEndpoint);
    procedure ParseScript;
    procedure Resolve;
  public
    constructor Create(const AInput: string);
    constructor CreateFromFile(const AFileName: string);
    destructor Destroy; override;
    { Parses (again) the input. HttpFile / Errors call it on first access. }
    procedure Parse;
    property HttpFile: THttpFile read GetHttpFile;
    property Errors: THttpParseErrorList read GetErrors;
    { register custom functions here before parsing }
    property Functions: THttpFunctionRegistry read FFunctions;
    property Context: THttpFunctionContext read FContext;
    { directory of the .env file used by $dotenv }
    property BaseDirectory: string read GetBaseDirectory write SetBaseDirectory;
  end;

implementation

type
  TBodyLine = record
    Text: string;
    Kind: THttpTokenKind;
    Row: Integer;
    Path: string;
    PathCol: Integer;
  end;

{ THttpFileParser }

constructor THttpFileParser.Create(const AInput: string);
begin
  inherited Create;
  FInput := AInput;
  FErrors := THttpParseErrorList.Create;
  FFunctions := THttpFunctionRegistry.Create(True);
  FContext := THttpFunctionContext.Create;
end;

constructor THttpFileParser.CreateFromFile(const AFileName: string);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    {$IFDEF FPC}
    Lines.LoadFromFile(AFileName);
    {$ELSE}
    Lines.LoadFromFile(AFileName, TEncoding.UTF8);
    {$ENDIF}
    Create(Lines.Text);
  finally
    Lines.Free;
  end;
  FContext.BaseDirectory := ExtractFilePath(ExpandFileName(AFileName));
end;

destructor THttpFileParser.Destroy;
begin
  FLexer.Free;
  FFile.Free;
  FContext.Free;
  FFunctions.Free;
  FErrors.Free;
  inherited Destroy;
end;

function THttpFileParser.GetBaseDirectory: string;
begin
  Result := FContext.BaseDirectory;
end;

procedure THttpFileParser.SetBaseDirectory(const AValue: string);
begin
  FContext.BaseDirectory := AValue;
end;

function THttpFileParser.GetHttpFile: THttpFile;
begin
  if not FParsed then
    Parse;
  Result := FFile;
end;

function THttpFileParser.GetErrors: THttpParseErrorList;
begin
  if not FParsed then
    Parse;
  Result := FErrors;
end;

procedure THttpFileParser.Parse;
begin
  FreeAndNil(FLexer);
  FreeAndNil(FFile);
  FErrors.Clear;
  FPendingName := '';
  FPendingTitle := '';
  FTokenIndex := 0;
  FFile := THttpFile.Create;
  FLexer := THttpFileLexer.Create(FInput);
  FToken := FLexer.NextToken;
  ParseHttpFile;
  Resolve;
  FErrors.SortByPosition;
  FParsed := True;
end;

procedure THttpFileParser.Resolve;
var
  Interpolator: THttpInterpolator;
begin
  Interpolator := THttpInterpolator.Create(FFile, FFunctions, FContext, FErrors);
  try
    Interpolator.Apply;
  finally
    Interpolator.Free;
  end;
end;

{ token handling }

procedure THttpFileParser.Advance;
begin
  if FToken.Kind <> tkEOF then
  begin
    FToken := FLexer.NextToken;
    Inc(FTokenIndex);
  end;
end;

procedure THttpFileParser.AddError(ARow, ACol: Integer; const AMessage, AToken, ARule: string);
begin
  FErrors.Add(ARow, ACol, AMessage, AToken, ARule);
end;

function THttpFileParser.DescribeToken: string;
begin
  Result := Trim(FToken.Raw);
  if Length(Result) > 40 then
    Result := Copy(Result, 1, 40) + '...';
end;

procedure THttpFileParser.Fail(const AMessage, ARule: string);
begin
  raise EHttpFileParseException.CreateAt(AMessage, FToken.Row, FToken.Col,
    DescribeToken, ARule);
end;

procedure THttpFileParser.Synchronize(AStartIndex: Integer);
begin
  if FTokenIndex = AStartIndex then
    Advance; // guarantee progress
  while not (FToken.Kind in [tkEOF, tkSeparator, tkMetaName, tkVariableDecl,
    tkRequestLine]) do
    Advance;
end;

{ grammar }

procedure THttpFileParser.ParseHttpFile;
var
  StartIndex: Integer;
begin
  while FToken.Kind <> tkEOF do
  begin
    StartIndex := FTokenIndex;
    try
      ParseItem;
    except
      on E: EHttpFileParseException do
      begin
        AddError(E.Row, E.Column, E.Message, E.Token, E.Rule);
        Synchronize(StartIndex);
      end;
    end;
  end;
end;

procedure THttpFileParser.ParseItem;
begin
  case FToken.Kind of
    tkBlank, tkComment: Advance;
    tkSeparator: ParseSeparator;
    tkMetaName: ParseMetaName;
    tkVariableDecl: ParseVariableDecl;
    tkRequestLine: ParseEndpoint;
    tkScript: ParseScript;
  else
    Fail('Unexpected "' + DescribeToken + '" outside of a request', 'HttpFile');
  end;
end;

procedure THttpFileParser.ParseSeparator;
begin
  FPendingName := '';
  FPendingTitle := FToken.Value;
  Advance;
end;

procedure THttpFileParser.ParseMetaName;
begin
  if FToken.Name = '' then
    AddError(FToken.Row, FToken.Col, 'Missing request name after @name',
      DescribeToken, 'MetaName')
  else
    FPendingName := FToken.Name;
  Advance;
end;

function THttpFileParser.ParseVariableDecl: TVariable;
begin
  Result := FFile.AddVariable;
  Result.Name := FToken.Name;
  Result.RawValue := FToken.Value;
  Result.Value := FToken.Value;
  Result.Row := FToken.Row;
  Result.Column := FToken.Col;
  Result.ValueColumn := FToken.ValueCol;
  Advance;
end;

function THttpFileParser.ParseEndpoint: TEndpoint;
var
  Tok: THttpToken;
begin
  Tok := FToken;
  if Tok.Value = '' then
  begin
    Advance;
    raise EHttpFileParseException.CreateAt('Missing URL in request line',
      Tok.Row, Tok.Col + Length(Tok.Name), Trim(Tok.Raw), 'RequestLine');
  end;
  Result := TEndpoint.Create;
  FFile.AddEndpoint(Result);
  ParseRequestLine(Result);
  ParseQueryContinuations(Result);
  if ParseHeaders(Result) then
    ParseBody(Result);
end;

procedure THttpFileParser.ParseRequestLine(AEndpoint: TEndpoint);
begin
  AEndpoint.Verb := FToken.Name;
  AEndpoint.RawUrl := FToken.Value;
  AEndpoint.Url := FToken.Value;
  if FToken.Version <> '' then
    AEndpoint.HttpRevision := FToken.Version;
  AEndpoint.Row := FToken.Row;
  AEndpoint.Column := FToken.Col;
  AEndpoint.UrlColumn := FToken.ValueCol;
  if FPendingName <> '' then
    AEndpoint.Name := FPendingName
  else
    AEndpoint.Name := FPendingTitle;
  FPendingName := '';
  FPendingTitle := '';
  Advance;
end;

procedure THttpFileParser.ParseQueryContinuations(AEndpoint: TEndpoint);
begin
  while FToken.Kind = tkQueryContinuation do
  begin
    AEndpoint.RawUrl := AEndpoint.RawUrl + FToken.Value;
    Advance;
  end;
  AEndpoint.Url := AEndpoint.RawUrl;
end;

function THttpFileParser.ParseHeaders(AEndpoint: TEndpoint): Boolean;
begin
  Result := False;
  while True do
    case FToken.Kind of
      tkHeaderLine: ParseHeader(AEndpoint);
      tkComment: Advance;
      tkScript: ParseScript;
      tkBlank:
        begin
          Advance;
          Result := True;
          Exit;
        end;
      tkEOF, tkSeparator, tkMetaName, tkVariableDecl, tkRequestLine:
        Exit;
    else
      AddError(FToken.Row, FToken.Col,
        'Expected a header ("Name: value") or a blank line, found "' +
        DescribeToken + '"', DescribeToken, 'HeaderLine');
      Advance;
    end;
end;

function THttpFileParser.ParseHeader(AEndpoint: TEndpoint): TRequestHeader;
begin
  Result := AEndpoint.AddRequestHeader;
  Result.Name := FToken.Name;
  Result.RawValue := FToken.Value;
  Result.Value := FToken.Value;
  Result.Row := FToken.Row;
  Result.Column := FToken.Col;
  Result.ValueColumn := FToken.ValueCol;
  Advance;
end;

procedure THttpFileParser.ParseBody(AEndpoint: TEndpoint);
var
  Lines: array of TBodyLine;
  Count, First, Last, I: Integer;
  PrevSoft, Done: Boolean;
  Joined: string;
begin
  Count := 0;
  PrevSoft := True;
  Done := False;
  while not Done do
  begin
    case FToken.Kind of
      tkEOF, tkSeparator, tkMetaName, tkVariableDecl:
        Done := True;
      tkRequestLine:
        Done := PrevSoft;
    end;
    if Done then
      Break;
    if FToken.Kind = tkScript then
    begin
      ParseScript;
      Continue;
    end;
    if Count = Length(Lines) then
      SetLength(Lines, Count * 2 + 8);
    Lines[Count].Text := FToken.Raw;
    Lines[Count].Kind := FToken.Kind;
    Lines[Count].Row := FToken.Row;
    Lines[Count].Path := FToken.Value;
    Lines[Count].PathCol := FToken.ValueCol;
    Inc(Count);
    PrevSoft := FToken.Kind in [tkBlank, tkComment];
    Advance;
  end;

  Last := Count - 1;
  while (Last >= 0) and (Lines[Last].Kind in [tkBlank, tkComment]) do
    Dec(Last);
  First := 0;
  while (First <= Last) and (Lines[First].Kind = tkBlank) do
    Inc(First);
  if First > Last then
    Exit;

  AEndpoint.BodyRow := Lines[First].Row;
  if (First = Last) and (Lines[First].Kind = tkFileRef) then
  begin
    AEndpoint.BodyFilePath := Lines[First].Path;
    AEndpoint.BodyFileColumn := Lines[First].PathCol;
    AEndpoint.RawRequestBody := Lines[First].Text;
    Exit;
  end;
  Joined := Lines[First].Text;
  for I := First + 1 to Last do
    Joined := Joined + #10 + Lines[I].Text;
  AEndpoint.RawRequestBody := Joined;
  AEndpoint.RequestBody := Joined;
end;

procedure THttpFileParser.ParseScript;
var
  Closed: Boolean;
  OpenAt: Integer;
begin
  AddError(FToken.Row, FToken.Col,
    'Request/response scripts are not supported', DescribeToken, 'Script');
  OpenAt := Pos('{%', FToken.Raw);
  Closed := Pos('%}', Copy(FToken.Raw, OpenAt + 2, MaxInt)) > 0;
  Advance;
  while (not Closed) and not (FToken.Kind in [tkEOF, tkSeparator]) do
  begin
    Closed := Pos('%}', FToken.Raw) > 0;
    Advance;
  end;
end;

end.
