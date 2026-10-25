unit Test_Reference_Unresolved;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, HttpFileParser, HttpFileAST, HttpFileResponses,
  HttpFileReferences, HttpFileScripting;

procedure ResponseReferenceWithoutResponseStaysRaw;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@t = {{login.response.body.$.id}}', '# @name login', 'GET http://x']));
  try
    AssertEqualsStr('{{login.response.body.$.id}}', P.HttpFile.Variables[0].Value);
    AssertEqualsInt(0, P.Errors.Count);
  finally P.Free; end;
end;

procedure UnknownRequestStaysRawWithoutError;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@t = {{createUser.response.body.$.id}}']));
  try
    AssertEqualsStr('{{createUser.response.body.$.id}}', P.HttpFile.Variables[0].Value);
    AssertEqualsInt(0, P.Errors.ErrorCount);
    AssertEqualsInt(1, P.Errors.WarningCount);
  finally P.Free; end;
end;

procedure MalformedReferenceToKnownRequestIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@t = {{login.response.cookies.x}}', '# @name login', 'GET http://x']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsInt(1, P.Errors[0].Row);
    AssertEqualsInt(6, P.Errors[0].Column);
    AssertEqualsStr('RequestReference', P.Errors[0].Rule);
  finally P.Free; end;
end;

procedure JsonPathFunctionIsNoLongerRegistered;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@t = {{$jsonpath ''a.b''}}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsStr('FunctionCall', P.Errors[0].Rule);
  finally P.Free; end;
end;

initialization
  RegisterTest('Reference.Unresolved', 'response reference without response stays raw', ResponseReferenceWithoutResponseStaysRaw);
  RegisterTest('Reference.Unresolved', 'unknown request stays raw without error', UnknownRequestStaysRawWithoutError);
  RegisterTest('Reference.Unresolved', 'malformed reference to known request is reported', MalformedReferenceToKnownRequestIsReported);
  RegisterTest('Reference.Unresolved', '$jsonpath function is no longer registered', JsonPathFunctionIsNoLongerRegistered);
end.
