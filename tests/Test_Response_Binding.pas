unit Test_Response_Binding;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, TestStubExecutor, HttpFileParser, HttpFileAST,
  HttpFileResponses, HttpFileResponseParser, HttpFileExecutor;

procedure StoredResponseFillsEndpoint;
var P: THttpFileParser; R: THttpResponse; E: TEndpoint;
begin
  P := NewParser(Lines(['# @name login', 'GET http://x', '', '# @name other', 'GET http://y']));
  try
    R := P.Responses.Put('login');
    R.StatusCode := 200; R.StatusText := 'OK'; R.Body := 'b'; R.AddHeader('X-A', '1');
    E := P.HttpFile.FindEndpoint('login');
    AssertEqualsInt(200, E.ResponseStatusCode);
    AssertEqualsStr('OK', E.ResponseStatusText);
    AssertEqualsStr('b', E.ResponseBody);
    AssertEqualsInt(1, Length(E.ResponseHeaders));
    AssertEqualsStr('X-A', E.ResponseHeaders[0].Name);
    AssertEqualsStr('1', E.ResponseHeaders[0].Value);
  finally P.Free; end;
end;

procedure EndpointWithoutStoredResponseStaysEmpty;
var P: THttpFileParser; E: TEndpoint;
begin
  P := NewParser(Lines(['# @name login', 'GET http://x']));
  try
    E := P.HttpFile.FindEndpoint('login');
    AssertEqualsInt(0, E.ResponseStatusCode);
    AssertEqualsStr('', E.ResponseBody);
    AssertEqualsInt(0, Length(E.ResponseHeaders));
  finally P.Free; end;
end;

procedure ParsingAgainDoesNotDuplicateHeaders;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['# @name login', 'GET http://x']));
  try
    P.Responses.Put('login').AddHeader('X-A', '1');
    P.Parse;
    P.Parse;
    AssertEqualsInt(1, Length(P.HttpFile.FindEndpoint('login').ResponseHeaders));
  finally P.Free; end;
end;

initialization
  RegisterTest('Response.Binding', 'stored response fills the endpoint', StoredResponseFillsEndpoint);
  RegisterTest('Response.Binding', 'endpoint without response stays empty', EndpointWithoutStoredResponseStaysEmpty);
  RegisterTest('Response.Binding', 'parsing again does not duplicate headers', ParsingAgainDoesNotDuplicateHeaders);
end.
