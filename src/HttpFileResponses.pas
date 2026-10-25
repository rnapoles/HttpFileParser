(* HttpFileResponses - responses of already executed requests, by request name.

  The parser never executes requests. An executor (HttpFileExecutor) or a
  loader (HttpFileResponseParser) stores each response here, the file is
  parsed again, and
  - expressions such as login.response.headers.X-AuthToken are replaced by the
    stored values
  - the endpoint with that name gets ResponseStatusCode, ResponseBody and
    ResponseHeaders (BindResponsesToEndpoints). *)
unit HttpFileResponses;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, HttpFileAST;

type
  THttpHeaderEntry = record
    Name: string;
    Value: string;
  end;

  THttpHeaderArray = array of THttpHeaderEntry;

  THttpResponse = class
  private
    FHeaders: THttpHeaderArray;
    function GetHeaderCount: Integer;
    function GetHeader(AIndex: Integer): THttpHeaderEntry;
  public
    HttpVersion: string;  // e.g. HTTP/1.1
    StatusCode: Integer;
    StatusText: string;
    Body: string;
    procedure Clear;
    procedure Assign(ASource: THttpResponse);
    procedure AddHeader(const AName, AValue: string);
    { header names are case-insensitive; the first match wins }
    function FindHeader(const AName: string; out AValue: string): Boolean;
    property HeaderCount: Integer read GetHeaderCount;
    property Headers[AIndex: Integer]: THttpHeaderEntry read GetHeader;
  end;

  THttpResponseStore = class
  private
    FResponses: TStringList; // request name -> THttpResponse (owned)
  public
    constructor Create;
    destructor Destroy; override;
    { creates (or replaces) the response of a request and returns it for filling }
    function Put(const ARequestName: string): THttpResponse;
    function Find(const ARequestName: string): THttpResponse; // nil when unknown
    procedure Clear;
  end;

{ copies the stored response of every named endpoint into the endpoint }
procedure BindResponsesToEndpoints(AFile: THttpFile; AStore: THttpResponseStore);

implementation

{ THttpResponse }

function THttpResponse.GetHeaderCount: Integer;
begin
  Result := Length(FHeaders);
end;

function THttpResponse.GetHeader(AIndex: Integer): THttpHeaderEntry;
begin
  Result := FHeaders[AIndex];
end;

procedure THttpResponse.Clear;
begin
  HttpVersion := '';
  StatusCode := 0;
  StatusText := '';
  Body := '';
  FHeaders := nil;
end;

procedure THttpResponse.Assign(ASource: THttpResponse);
var
  I: Integer;
begin
  Clear;
  HttpVersion := ASource.HttpVersion;
  StatusCode := ASource.StatusCode;
  StatusText := ASource.StatusText;
  Body := ASource.Body;
  for I := 0 to ASource.HeaderCount - 1 do
    AddHeader(ASource.Headers[I].Name, ASource.Headers[I].Value);
end;

procedure THttpResponse.AddHeader(const AName, AValue: string);
begin
  SetLength(FHeaders, Length(FHeaders) + 1);
  FHeaders[High(FHeaders)].Name := AName;
  FHeaders[High(FHeaders)].Value := AValue;
end;

function THttpResponse.FindHeader(const AName: string; out AValue: string): Boolean;
var
  I: Integer;
begin
  AValue := '';
  for I := 0 to High(FHeaders) do
    if SameText(FHeaders[I].Name, AName) then
    begin
      AValue := FHeaders[I].Value;
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ THttpResponseStore }

constructor THttpResponseStore.Create;
begin
  inherited Create;
  FResponses := TStringList.Create;
  FResponses.CaseSensitive := True;
  FResponses.OwnsObjects := True;
end;

destructor THttpResponseStore.Destroy;
begin
  FResponses.Free;
  inherited Destroy;
end;

function THttpResponseStore.Put(const ARequestName: string): THttpResponse;
var
  Idx: Integer;
begin
  Idx := FResponses.IndexOf(ARequestName);
  if Idx >= 0 then
    FResponses.Delete(Idx);
  Result := THttpResponse.Create;
  FResponses.AddObject(ARequestName, Result);
end;

function THttpResponseStore.Find(const ARequestName: string): THttpResponse;
var
  Idx: Integer;
begin
  Idx := FResponses.IndexOf(ARequestName);
  if Idx >= 0 then
    Result := THttpResponse(FResponses.Objects[Idx])
  else
    Result := nil;
end;

procedure THttpResponseStore.Clear;
begin
  FResponses.Clear;
end;

procedure BindResponsesToEndpoints(AFile: THttpFile; AStore: THttpResponseStore);
var
  I, J: Integer;
  Endpoint: TEndpoint;
  Response: THttpResponse;
  Header: TResponseHeader;
begin
  for I := 0 to High(AFile.Endpoints) do
  begin
    Endpoint := AFile.Endpoints[I];
    if Endpoint.Name = '' then
      Continue;
    Response := AStore.Find(Endpoint.Name);
    if Response = nil then
      Continue;
    Endpoint.ResponseStatusCode := Response.StatusCode;
    Endpoint.ResponseStatusText := Response.StatusText;
    Endpoint.ResponseBody := Response.Body;
    for J := 0 to Response.HeaderCount - 1 do
    begin
      Header := Endpoint.AddResponseHeader;
      Header.Name := Response.Headers[J].Name;
      Header.Value := Response.Headers[J].Value;
      Header.RawValue := Response.Headers[J].Value;
    end;
  end;
end;

end.
