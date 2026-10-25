unit Test_Reference_RequestScope;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, HttpFileParser, HttpFileAST, HttpFileResponses,
  HttpFileReferences, HttpFileScripting;

procedure ReadsEarlierRequestBodyAndHeader;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['# @name first', 'POST http://x', 'Content-Type: application/json', '', '{"id":7}', '',
    '# @name second', 'GET http://y/{{first.request.body.$.id}}', 'X-Type: {{first.request.headers.content-type}}']));
  try
    AssertEqualsStr('http://y/7', P.HttpFile.FindEndpoint('second').Url);
    AssertEqualsStr('application/json', P.HttpFile.FindEndpoint('second').RequestHeaders[0].Value);
    AssertEqualsInt(0, P.Errors.Count);
  finally P.Free; end;
end;

procedure ReadsLaterRequest;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['# @name a', 'GET http://x/{{b.request.body.$.id}}', '', '# @name b', 'POST http://y', '', '{"id":9}']));
  try
    AssertEqualsStr('http://x/9', P.HttpFile.FindEndpoint('a').Url);
  finally P.Free; end;
end;

procedure RequestValueIsUsableInVariables;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@id = {{a.request.body.$.id}}', '# @name a', 'POST http://x', '', '{"id":3}']));
  try
    AssertEqualsStr('3', P.HttpFile.Variables[0].Value);
  finally P.Free; end;
end;

procedure CircularRequestReferenceIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['# @name a', 'POST http://x', '', '{{b.request.body.*}}', '',
    '# @name b', 'POST http://y', '', '{{a.request.body.*}}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertTrue(Pos('Circular', P.Errors[0].Message) > 0);
  finally P.Free; end;
end;

procedure FileBodyCannotBeSelected;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@v = {{a.request.body.*}}', '# @name a', 'POST http://x', '', '< ./a.json']));
  try
    AssertEqualsInt(1, P.Errors.Count);
  finally P.Free; end;
end;

initialization
  RegisterTest('Reference.RequestScope', 'reads earlier request body and header', ReadsEarlierRequestBodyAndHeader);
  RegisterTest('Reference.RequestScope', 'reads a later request', ReadsLaterRequest);
  RegisterTest('Reference.RequestScope', 'value is usable in variables', RequestValueIsUsableInVariables);
  RegisterTest('Reference.RequestScope', 'circular request reference is reported', CircularRequestReferenceIsReported);
  RegisterTest('Reference.RequestScope', 'file body cannot be selected', FileBodyCannotBeSelected);
end.
