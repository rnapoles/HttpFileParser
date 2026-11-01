unit Test_Linter_Placeholders;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, TestLintHelpers, HttpFileParser, HttpFileAST, HttpFileLinter;

const Rule = 'lint-unresolved-placeholder';

function Count(const ASource: string): Integer;
var L: THttpParseErrorList;
begin
  L := LintSource(ASource);
  try Result := CountRule(L, Rule); finally L.Free; end;
end;

procedure UnknownNameIsReportedWithRange;
var L: THttpParseErrorList; I: Integer;
begin
  L := LintSource('GET http://{{host}}/x');
  try
    I := IndexOfRule(L, Rule);
    AssertTrue(I >= 0);
    AssertEqualsInt(1, L[I].Row);
    AssertEqualsInt(12, L[I].Column);
    AssertEqualsInt(20, L[I].EndColumn);
    AssertTrue(L[I].Severity = hsWarning);
  finally L.Free; end;
end;

procedure PositionInsideABodyUsesItsRow;
var L: THttpParseErrorList; I: Integer;
begin
  L := LintSource(Lines(['POST http://x', '', 'line {{nope}}']));
  try
    I := IndexOfRule(L, Rule);
    AssertEqualsInt(3, L[I].Row);
    AssertEqualsInt(6, L[I].Column);
  finally L.Free; end;
end;

procedure KnownThingsAreNotReported;
begin
  AssertEqualsInt(0, Count(Lines(['@h = http://z', 'GET {{h}}/a'])));                      // variable
  AssertEqualsInt(0, Count(Lines(['# @name a', 'GET http://x', '', 'GET http://y/{{a.response.body.$.id}}']))); // reference
  AssertEqualsInt(0, Count('GET http://x/{{$guid}}'));                                      // function
end;

procedure UnknownFunctionIsReported;
begin
  AssertEqualsInt(1, Count('GET http://x/{{$nope 1}}'));
end;

procedure MalformedReferenceToAKnownRequestIsReported;
begin
  AssertEqualsInt(1, Count(Lines(['# @name a', 'GET http://x', '', 'GET http://y/{{a.response.cookies.x}}'])));
end;

procedure RegisteredObjectIsKnown;
var P: THttpFileParser; Person: TPerson; L: THttpParseErrorList;
begin
  Person := NewPerson;
  P := NewParser('GET http://x/{{person.Name}}/{{stranger.Name}}');
  try
    P.Scripting.RegisterObject('person', Person);
    L := LintParser(P);
    try AssertEqualsInt(1, CountRule(L, Rule)); finally L.Free; end;
  finally P.Free; Person.Free; end;
end;

initialization
  RegisterTest('Linter.Placeholders', 'unknown name is reported with its range', UnknownNameIsReportedWithRange);
  RegisterTest('Linter.Placeholders', 'position inside a body uses its row', PositionInsideABodyUsesItsRow);
  RegisterTest('Linter.Placeholders', 'known variable, reference and function are not reported', KnownThingsAreNotReported);
  RegisterTest('Linter.Placeholders', 'unknown function is reported', UnknownFunctionIsReported);
  RegisterTest('Linter.Placeholders', 'malformed reference to a known request is reported', MalformedReferenceToAKnownRequestIsReported);
  RegisterTest('Linter.Placeholders', 'registered object is known', RegisteredObjectIsKnown);
end.
