(* HttpFileResponses - responses of already executed requests, by request name.

  The parser never executes requests. The HTTP client stores each response
  here (Parser.Responses.Put('login')...) and parses again; expressions such
  as login.response.headers.X-AuthToken inside double braces are then
  replaced by the stored values. *)
unit HttpFileResponses;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes;

type
  THttpHeaderEntry = record
    Name: string;
    Value: string;
  end;

  THttpResponse = class
  private
    FHeaders: array of THttpHeaderEntry;
    function GetHeaderCount: Integer;
    function GetHeader(AIndex: Integer): THttpHeaderEntry;
  public
    StatusCode: Integer;
    Body: string;
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

end.
