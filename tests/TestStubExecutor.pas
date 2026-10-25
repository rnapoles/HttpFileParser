unit TestStubExecutor;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
interface
uses SysUtils, Classes, HttpFileResponses, HttpFileParser, HttpFileExecutor;

type
  { transport double: answers by URL (404 when unknown) and records the messages }
  TStubRequestExecutor = class(TRequestExecutor)
  private
    FSent: array of THttpRequestMessage;
    FReplies: TStringList; // url -> THttpResponse (owned)
  protected
    function DoSend(const ARequest: THttpRequestMessage): THttpResponse; override;
  public
    constructor Create(AParser: THttpFileParser);
    destructor Destroy; override;
    function Reply(const AUrl: string; AStatus: Integer; const ABody: string): THttpResponse;
    function BodyBytes(const ARequest: THttpRequestMessage): RawByteString;
    function SentCount: Integer;
    function Sent(AIndex: Integer): THttpRequestMessage;
  end;

implementation

constructor TStubRequestExecutor.Create(AParser: THttpFileParser);
begin
  inherited Create(AParser);
  FReplies := TStringList.Create;
  FReplies.OwnsObjects := True;
end;

destructor TStubRequestExecutor.Destroy;
begin
  FReplies.Free;
  inherited Destroy;
end;

function TStubRequestExecutor.Reply(const AUrl: string; AStatus: Integer;
  const ABody: string): THttpResponse;
begin
  Result := THttpResponse.Create;
  Result.HttpVersion := 'HTTP/1.1';
  Result.StatusCode := AStatus;
  Result.Body := ABody;
  FReplies.AddObject(AUrl, Result);
end;

function TStubRequestExecutor.DoSend(const ARequest: THttpRequestMessage): THttpResponse;
var
  Idx: Integer;
begin
  SetLength(FSent, Length(FSent) + 1);
  FSent[High(FSent)] := ARequest;
  Result := THttpResponse.Create;
  Idx := FReplies.IndexOf(ARequest.Url);
  if Idx >= 0 then
    Result.Assign(THttpResponse(FReplies.Objects[Idx]))
  else
  begin
    Result.HttpVersion := 'HTTP/1.1';
    Result.StatusCode := 404;
    Result.StatusText := 'Not Found';
  end;
end;

function TStubRequestExecutor.BodyBytes(const ARequest: THttpRequestMessage): RawByteString;
begin
  Result := ReadBodyBytes(ARequest);
end;

function TStubRequestExecutor.SentCount: Integer;
begin
  Result := Length(FSent);
end;

function TStubRequestExecutor.Sent(AIndex: Integer): THttpRequestMessage;
begin
  Result := FSent[AIndex];
end;

end.
