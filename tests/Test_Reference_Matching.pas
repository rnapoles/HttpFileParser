unit Test_Reference_Matching;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, HttpFileParser, HttpFileAST, HttpFileResponses,
  HttpFileReferences, HttpFileScripting;

function Match(const AInner: string; out ARef: TRequestReference; out AMessage: string): TReferenceMatch;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['# @name login', 'GET http://x', '', '# @name my.req', 'GET http://y']));
  try Result := MatchRequestReference(P.HttpFile, AInner, ARef, AMessage); finally P.Free; end;
end;

procedure ResponseHeaderReference;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('login.response.headers.X-AuthToken', R, M) = rmValid);
  AssertEqualsStr('login', R.RequestName);
  AssertTrue(R.Scope = rsResponse);
  AssertTrue(R.Part = rpHeaders);
  AssertEqualsStr('X-AuthToken', R.Selector);
end;

procedure BodyJsonPathKeepsDotsAndBrackets;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('login.response.body.$.payload.items[0].id', R, M) = rmValid);
  AssertEqualsStr('$.payload.items[0].id', R.Selector);
end;

procedure WholeBodySelector;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('login.request.body.*', R, M) = rmValid);
  AssertTrue(R.Scope = rsRequest);
  AssertEqualsStr('*', R.Selector);
end;

procedure RequestNameMayContainDots;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('my.req.request.body.*', R, M) = rmValid);
  AssertEqualsStr('my.req', R.RequestName);
end;

procedure ScopeAndPartIgnoreCase;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('login.RESPONSE.Headers.x', R, M) = rmValid);
end;

procedure UnknownRequestIsNotAReference;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('other.response.body.*', R, M) = rmNotAReference);
  AssertTrue(Match('plainVariable', R, M) = rmNotAReference);
end;

procedure UnknownPartIsInvalid;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('login.response.cookies.a', R, M) = rmInvalid);
end;

procedure MissingSelectorIsInvalid;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('login.response.headers', R, M) = rmInvalid);
  AssertTrue(Match('login.response', R, M) = rmInvalid);
end;

procedure XPathIsNotSupported;
var R: TRequestReference; M: string;
begin
  AssertTrue(Match('login.response.body.//a/b', R, M) = rmInvalid);
  AssertTrue(Pos('XPath', M) > 0);
end;

initialization
  RegisterTest('Reference.Matching', 'response header reference', ResponseHeaderReference);
  RegisterTest('Reference.Matching', 'body JSONPath keeps dots and brackets', BodyJsonPathKeepsDotsAndBrackets);
  RegisterTest('Reference.Matching', 'whole body selector', WholeBodySelector);
  RegisterTest('Reference.Matching', 'request name may contain dots', RequestNameMayContainDots);
  RegisterTest('Reference.Matching', 'scope and part ignore case', ScopeAndPartIgnoreCase);
  RegisterTest('Reference.Matching', 'unknown request is not a reference', UnknownRequestIsNotAReference);
  RegisterTest('Reference.Matching', 'unknown part is invalid', UnknownPartIsInvalid);
  RegisterTest('Reference.Matching', 'missing selector is invalid', MissingSelectorIsInvalid);
  RegisterTest('Reference.Matching', 'XPath is not supported', XPathIsNotSupported);
end.
