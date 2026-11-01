unit Test_Linter_DuplicateNames;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, TestLintHelpers, HttpFileParser, HttpFileAST, HttpFileLinter;

const Rule = 'lint-duplicate-request';

procedure ReportsTheSecondRequestWithItsPosition;
var L: THttpParseErrorList; I: Integer;
begin
  L := LintSource(Lines(['# @name a', 'GET http://x', '', '# @name a', 'GET http://y']));
  try
    AssertEqualsInt(1, CountRule(L, Rule));
    I := IndexOfRule(L, Rule);
    AssertTrue(L[I].Severity = hsWarning);
    AssertEqualsInt(5, L[I].Row);
    AssertEqualsInt(1, L[I].Column);
    AssertEqualsInt(4, L[I].EndColumn);
    AssertTrue(Pos('line 2', L[I].Message) > 0, L[I].Message);
  finally L.Free; end;
end;

procedure UniqueNamesAreFine;
var L: THttpParseErrorList;
begin
  L := LintSource(Lines(['# @name a', 'GET http://x', '', '# @name b', 'GET http://y']));
  try AssertEqualsInt(0, CountRule(L, Rule)); finally L.Free; end;
end;

procedure UnnamedRequestsCannotClash;
var L: THttpParseErrorList;
begin
  L := LintSource(Lines(['GET http://x', '', 'GET http://y']));
  try AssertEqualsInt(0, CountRule(L, Rule)); finally L.Free; end;
end;

procedure EveryExtraDefinitionIsReported;
var L: THttpParseErrorList;
begin
  L := LintSource(Lines(['# @name a', 'GET http://x', '', '# @name a', 'GET http://y', '',
    '# @name a', 'GET http://z']));
  try AssertEqualsInt(2, CountRule(L, Rule)); finally L.Free; end;
end;

initialization
  RegisterTest('Linter.DuplicateNames', 'reports the second request with its position', ReportsTheSecondRequestWithItsPosition);
  RegisterTest('Linter.DuplicateNames', 'unique names are fine', UniqueNamesAreFine);
  RegisterTest('Linter.DuplicateNames', 'unnamed requests cannot clash', UnnamedRequestsCannotClash);
  RegisterTest('Linter.DuplicateNames', 'every extra definition is reported', EveryExtraDefinitionIsReported);
end.
