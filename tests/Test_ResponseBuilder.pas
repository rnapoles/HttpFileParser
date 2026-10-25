unit Test_ResponseBuilder;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, HttpFileResponses, HttpFileResponseParser, HttpFileResponseBuilder;

procedure AddHeader(B: THttpResponseBuilder; const ALine: AnsiString);
begin
  B.AddHeaderData(PAnsiChar(ALine), Length(ALine));
end;

procedure AddBody(B: THttpResponseBuilder; const AChunk: AnsiString);
begin
  B.AddBodyData(PAnsiChar(AChunk), Length(AChunk));
end;

procedure BuildsFromHeaderLinesAndBodyChunks;
var B: THttpResponseBuilder; R: THttpResponse; V: string;
begin
  B := THttpResponseBuilder.Create;
  try
    AddHeader(B, 'HTTP/1.1 200 OK'#13#10);
    AddHeader(B, 'X-AuthToken: abc'#13#10);
    AddHeader(B, #13#10);
    AddBody(B, '{"id":');
    AddBody(B, '7}');
    R := B.Build;
    try
      AssertEqualsInt(200, R.StatusCode);
      AssertTrue(R.FindHeader('x-authtoken', V));
      AssertEqualsStr('abc', V);
      AssertEqualsStr('{"id":7}', R.Body);
    finally R.Free; end;
  finally B.Free; end;
end;

procedure RedirectKeepsOnlyTheFinalResponse;
var B: THttpResponseBuilder; R: THttpResponse; V: string;
begin
  B := THttpResponseBuilder.Create;
  try
    AddHeader(B, 'HTTP/1.1 302 Found'#13#10);
    AddHeader(B, 'Location: /next'#13#10);
    AddHeader(B, #13#10);
    AddBody(B, 'redirect page');
    AddHeader(B, 'HTTP/1.1 200 OK'#13#10);
    AddHeader(B, 'X-Final: yes'#13#10);
    AddHeader(B, #13#10);
    AddBody(B, 'final');
    R := B.Build;
    try
      AssertEqualsInt(200, R.StatusCode);
      AssertEqualsInt(1, R.HeaderCount);
      AssertTrue(not R.FindHeader('Location', V));
      AssertEqualsStr('final', R.Body);
    finally R.Free; end;
  finally B.Free; end;
end;

procedure InterimResponseIsDiscarded;
var B: THttpResponseBuilder; R: THttpResponse;
begin
  B := THttpResponseBuilder.Create;
  try
    AddHeader(B, 'HTTP/1.1 100 Continue'#13#10);
    AddHeader(B, #13#10);
    AddHeader(B, 'HTTP/2 201'#13#10);
    AddHeader(B, #13#10);
    R := B.Build;
    try
      AssertEqualsInt(201, R.StatusCode);
      AssertEqualsStr('', R.Body);
    finally R.Free; end;
  finally B.Free; end;
end;

procedure ClearStartsOver;
var B: THttpResponseBuilder; R: THttpResponse;
begin
  B := THttpResponseBuilder.Create;
  try
    AddHeader(B, 'HTTP/1.1 500 Oops'#13#10#13#10);
    B.Clear;
    AddHeader(B, 'HTTP/1.1 204 No Content'#13#10#13#10);
    R := B.Build;
    try AssertEqualsInt(204, R.StatusCode); finally R.Free; end;
  finally B.Free; end;
end;

procedure NothingReceivedIsReported;
var B: THttpResponseBuilder; Raised: Boolean;
begin
  B := THttpResponseBuilder.Create;
  Raised := False;
  try
    try B.Build.Free; except on EHttpResponseError do Raised := True; end;
  finally B.Free; end;
  AssertTrue(Raised);
end;

initialization
  RegisterTest('ResponseBuilder', 'builds from header lines and body chunks', BuildsFromHeaderLinesAndBodyChunks);
  RegisterTest('ResponseBuilder', 'redirect keeps only the final response', RedirectKeepsOnlyTheFinalResponse);
  RegisterTest('ResponseBuilder', 'interim response is discarded', InterimResponseIsDiscarded);
  RegisterTest('ResponseBuilder', 'Clear starts over', ClearStartsOver);
  RegisterTest('ResponseBuilder', 'nothing received is reported', NothingReceivedIsReported);
end.
