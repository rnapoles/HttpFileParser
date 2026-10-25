(* HttpFileExecutor - runs the requests of a parsed .http file.

  IRequestExecutor is what callers depend on. TRequestExecutor is the template:
  for each request it
    1. checks that every response the request refers to is already stored
    2. builds a transport neutral THttpRequestMessage from the endpoint
    3. hands it to DoSend (the only method a concrete executor implements)
    4. stores the response under the request name (Parser.Responses)
    5. parses the file again so the next request resolves
       name.response.headers.X / name.response.body.$.id
  A new transport (libcurl, Indy, Synapse, a test double) is one subclass
  that overrides DoSend; nothing else changes.

  Parsing again recreates the endpoint objects: never keep a TEndpoint across
  Execute calls, address requests by name or index. The executor does not own
  the parser. It owns LastResponse; the stored copy belongs to the parser's
  response store. *)
unit HttpFileExecutor;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, HttpFileAST, HttpFileResponses, HttpFileReferences,
  HttpFileParser;

type
  ERequestExecutor = class(Exception);

  { Everything a transport needs; values are fully resolved. }
  THttpRequestMessage = record
    Method: string;
    Url: string;
    HttpVersion: string;       // e.g. HTTP/1.1
    Headers: THttpHeaderArray;
    Body: string;              // used when BodyFilePath is empty
    BodyFilePath: string;      // absolute (or as written when the base is unknown)
  end;

  IRequestExecutor = interface
    ['{7C1D5E0B-3A55-4B7E-9A46-2D8F61C0B9E3}']
    { runs the request at AIndex (0-based) and returns its response }
    function ExecuteAt(AIndex: Integer): THttpResponse;
    function Execute(const ARequestName: string): THttpResponse;
    procedure ExecuteAll;
  end;

  TRequestExecutedEvent = procedure(ASender: TObject; const ARequestName: string;
    AResponse: THttpResponse) of object;

  TRequestExecutor = class(TInterfacedObject, IRequestExecutor)
  private
    FParser: THttpFileParser;
    FLastResponse: THttpResponse;
    FOnExecuted: TRequestExecutedEvent;
    procedure EnsureResolved(AEndpoint: TEndpoint);
    function IndexOfRequest(const ARequestName: string): Integer;
  protected
    { sends the message; returns a new response that the executor takes over }
    function DoSend(const ARequest: THttpRequestMessage): THttpResponse; virtual; abstract;
    { the body as bytes: the file content, or the text as UTF-8 }
    function ReadBodyBytes(const ARequest: THttpRequestMessage): RawByteString;
  public
    constructor Create(AParser: THttpFileParser);
    destructor Destroy; override;
    function ExecuteAt(AIndex: Integer): THttpResponse;
    function Execute(const ARequestName: string): THttpResponse;
    procedure ExecuteAll;
    property Parser: THttpFileParser read FParser;
    { the response of the latest Execute call; valid until the next one }
    property LastResponse: THttpResponse read FLastResponse;
    property OnExecuted: TRequestExecutedEvent read FOnExecuted write FOnExecuted;
  end;

function BuildRequestMessage(AEndpoint: TEndpoint; const ABaseDirectory: string): THttpRequestMessage;

{ True unless APath is absolute: starts with / or \, has a drive ("C:") or is a
  UNC path. Platform independent, so a Windows path in a file is recognised on
  every system. }
function IsRelativePath(const APath: string): Boolean;

implementation

function IsRelativePath(const APath: string): Boolean;
begin
  if APath = '' then
    Result := True
  else if (APath[1] = '/') or (APath[1] = '\') then
    Result := False
  else if (Length(APath) >= 2) and (APath[2] = ':') and
          (((APath[1] >= 'a') and (APath[1] <= 'z')) or ((APath[1] >= 'A') and (APath[1] <= 'Z'))) then
    Result := False
  else
    Result := True;
end;

function BuildRequestMessage(AEndpoint: TEndpoint; const ABaseDirectory: string): THttpRequestMessage;
var
  I: Integer;
begin
  Result.Method := UpperCase(AEndpoint.Verb);
  Result.Url := AEndpoint.Url;
  Result.HttpVersion := AEndpoint.HttpRevision;
  Result.Headers := nil;
  Result.Body := AEndpoint.RequestBody;
  Result.BodyFilePath := AEndpoint.BodyFilePath;
  SetLength(Result.Headers, Length(AEndpoint.RequestHeaders));
  for I := 0 to High(AEndpoint.RequestHeaders) do
  begin
    Result.Headers[I].Name := AEndpoint.RequestHeaders[I].Name;
    Result.Headers[I].Value := AEndpoint.RequestHeaders[I].Value;
  end;
  if (Result.BodyFilePath <> '') and IsRelativePath(Result.BodyFilePath) and
     (ABaseDirectory <> '') then
    Result.BodyFilePath := ExpandFileName(
      IncludeTrailingPathDelimiter(ABaseDirectory) + Result.BodyFilePath);
end;

{ TRequestExecutor }

constructor TRequestExecutor.Create(AParser: THttpFileParser);
begin
  inherited Create;
  if AParser = nil then
    raise ERequestExecutor.Create('A parser is required');
  FParser := AParser;
end;

destructor TRequestExecutor.Destroy;
begin
  FLastResponse.Free;
  inherited Destroy;
end;

function TRequestExecutor.ReadBodyBytes(const ARequest: THttpRequestMessage): RawByteString;
var
  Stream: TFileStream;
begin
  Result := '';
  if ARequest.BodyFilePath <> '' then
  begin
    if not FileExists(ARequest.BodyFilePath) then
      raise ERequestExecutor.CreateFmt('Body file not found: %s', [ARequest.BodyFilePath]);
    Stream := TFileStream.Create(ARequest.BodyFilePath, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, Stream.Size);
      if Stream.Size > 0 then
        Stream.ReadBuffer(Result[1], Stream.Size);
    finally
      Stream.Free;
    end;
  end
  else
  begin
    {$IFDEF FPC}
    Result := ARequest.Body;            // FPC strings already hold UTF-8 bytes
    {$ELSE}
    Result := UTF8Encode(ARequest.Body);
    {$ENDIF}
  end;
end;

function TRequestExecutor.IndexOfRequest(const ARequestName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FParser.HttpFile.Endpoints) do
    if FParser.HttpFile.Endpoints[I].Name = ARequestName then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure TRequestExecutor.EnsureResolved(AEndpoint: TEndpoint);
  procedure Check(const AWhere, AText: string);
  begin
    if HasRequestReference(FParser.HttpFile, AText) then
      raise ERequestExecutor.CreateFmt(
        'Request "%s" (line %d) uses a response that is not available yet (%s: %s). ' +
        'Execute the request it refers to first.',
        [AEndpoint.Name, AEndpoint.Row, AWhere, AText]);
  end;
var
  I: Integer;
begin
  Check('url', AEndpoint.Url);
  for I := 0 to High(AEndpoint.RequestHeaders) do
    Check('header ' + AEndpoint.RequestHeaders[I].Name, AEndpoint.RequestHeaders[I].Value);
  if AEndpoint.BodyFilePath = '' then
    Check('body', AEndpoint.RequestBody);
end;

function TRequestExecutor.ExecuteAt(AIndex: Integer): THttpResponse;
var
  Endpoint: TEndpoint;
  RequestName: string;
  Received: THttpResponse;
begin
  if (AIndex < 0) or (AIndex > High(FParser.HttpFile.Endpoints)) then
    raise ERequestExecutor.CreateFmt('Request index %d is out of range', [AIndex]);
  Endpoint := FParser.HttpFile.Endpoints[AIndex];
  RequestName := Endpoint.Name;
  EnsureResolved(Endpoint);

  Received := DoSend(BuildRequestMessage(Endpoint, FParser.BaseDirectory));
  if Received = nil then
    raise ERequestExecutor.CreateFmt('The transport returned no response for "%s"', [RequestName]);
  FLastResponse.Free;
  FLastResponse := Received;

  if RequestName <> '' then
    FParser.Responses.Put(RequestName).Assign(FLastResponse);
  FParser.Parse; // the endpoint objects are recreated: do not touch Endpoint below

  if Assigned(FOnExecuted) then
    FOnExecuted(Self, RequestName, FLastResponse);
  Result := FLastResponse;
end;

function TRequestExecutor.Execute(const ARequestName: string): THttpResponse;
var
  Idx: Integer;
begin
  Idx := IndexOfRequest(ARequestName);
  if Idx < 0 then
    raise ERequestExecutor.CreateFmt('Unknown request "%s"', [ARequestName]);
  Result := ExecuteAt(Idx);
end;

procedure TRequestExecutor.ExecuteAll;
var
  I, Count: Integer;
begin
  Count := Length(FParser.HttpFile.Endpoints);
  for I := 0 to Count - 1 do
    ExecuteAt(I);
end;

end.
