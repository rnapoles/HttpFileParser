unit Test_Reference_ResponseHeaders;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, HttpFileParser, HttpFileAST, HttpFileResponses,
  HttpFileReferences, HttpFileScripting;

function Source(const AHeader: string): string;
begin
  Result := Lines(['@t = {{login.response.headers.' + AHeader + '}}', '# @name login', 'GET http://x']);
end;

procedure HeaderNameIsCaseInsensitive;
var P: THttpFileParser;
begin
  P := NewParser(Source('x-authtoken'));
  try
    P.Responses.Put('login').AddHeader('X-AuthToken', 'abc');
    AssertEqualsStr('abc', P.HttpFile.Variables[0].Value);
    AssertEqualsInt(0, P.Errors.Count);
  finally P.Free; end;
end;

procedure MissingHeaderIsReportedAndKeptRaw;
var P: THttpFileParser;
begin
  P := NewParser(Source('X-Nope'));
  try
    P.Responses.Put('login').AddHeader('X-AuthToken', 'abc');
    AssertEqualsStr('{{login.response.headers.X-Nope}}', P.HttpFile.Variables[0].Value);
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsStr('RequestReference', P.Errors[0].Rule);
  finally P.Free; end;
end;

procedure HeaderValueIsUsableInLaterRequests;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@t = {{login.response.headers.X-AuthToken}}', '# @name login', 'POST http://x', '',
    '# @name next', 'GET http://y', 'Authorization: Bearer {{t}}']));
  try
    P.Responses.Put('login').AddHeader('X-AuthToken', 'abc');
    AssertEqualsStr('Bearer abc', P.HttpFile.Endpoints[1].RequestHeaders[0].Value);
  finally P.Free; end;
end;

procedure ParsingAgainPicksUpNewResponses;
var P: THttpFileParser;
begin
  P := NewParser(Source('X-AuthToken'));
  try
    AssertEqualsStr('{{login.response.headers.X-AuthToken}}', P.HttpFile.Variables[0].Value);
    P.Responses.Put('login').AddHeader('X-AuthToken', 'xyz');
    P.Parse;
    AssertEqualsStr('xyz', P.HttpFile.Variables[0].Value);
  finally P.Free; end;
end;

initialization
  RegisterTest('Reference.ResponseHeaders', 'header name is case-insensitive', HeaderNameIsCaseInsensitive);
  RegisterTest('Reference.ResponseHeaders', 'missing header is reported and kept raw', MissingHeaderIsReportedAndKeptRaw);
  RegisterTest('Reference.ResponseHeaders', 'value is usable in later requests', HeaderValueIsUsableInLaterRequests);
  RegisterTest('Reference.ResponseHeaders', 'parsing again picks up new responses', ParsingAgainPicksUpNewResponses);
end.
