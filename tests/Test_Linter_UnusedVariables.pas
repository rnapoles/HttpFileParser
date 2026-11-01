unit Test_Linter_UnusedVariables;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, TestLintHelpers, HttpFileParser, HttpFileAST, HttpFileLinter;

const Rule = 'lint-unused-variable';

function Unused(const ASource: string): Integer;
var L: THttpParseErrorList;
begin
  L := LintSource(ASource);
  try Result := CountRule(L, Rule); finally L.Free; end;
end;

procedure ReportsAnUnusedVariableWithItsPosition;
var L: THttpParseErrorList; I: Integer;
begin
  L := LintSource(Lines(['', '  @a = 1']));
  try
    I := IndexOfRule(L, Rule);
    AssertTrue(I >= 0);
    AssertEqualsInt(2, L[I].Row);
    AssertEqualsInt(3, L[I].Column);
    AssertEqualsInt(5, L[I].EndColumn); // "@a"
    AssertTrue(L[I].Severity = hsWarning);
  finally L.Free; end;
end;

procedure UsedInUrlHeaderOrBodyIsFine;
begin
  AssertEqualsInt(0, Unused(Lines(['@a = 1', 'POST http://x/{{a}}'])));
  AssertEqualsInt(0, Unused(Lines(['@a = 1', 'POST http://x', 'X: {{a}}'])));
  AssertEqualsInt(0, Unused(Lines(['@a = 1', 'POST http://x', '', 'v={{a}}'])));
end;

procedure UsedByAnotherVariableIsFine;
begin
  AssertEqualsInt(0, Unused(Lines(['@a = 1', '@b = {{a}}', 'GET http://x/{{b}}'])));
end;

procedure UsedOnlyByItselfIsUnused;
begin
  AssertEqualsInt(1, Unused('@a = {{a}}'));
end;

procedure MentionInACommentIsNotAUse;
begin
  AssertEqualsInt(1, Unused(Lines(['@a = 1', '# {{a}}', 'GET http://x'])));
end;

procedure UnusedOnesAreReportedIndividually;
begin
  AssertEqualsInt(2, Unused(Lines(['@a = 1', '@b = 2', '@c = 3', 'GET http://x/{{c}}'])));
end;

initialization
  RegisterTest('Linter.UnusedVariables', 'reports an unused variable with its position', ReportsAnUnusedVariableWithItsPosition);
  RegisterTest('Linter.UnusedVariables', 'used in url, header or body is fine', UsedInUrlHeaderOrBodyIsFine);
  RegisterTest('Linter.UnusedVariables', 'used by another variable is fine', UsedByAnotherVariableIsFine);
  RegisterTest('Linter.UnusedVariables', 'used only by itself is unused', UsedOnlyByItselfIsUnused);
  RegisterTest('Linter.UnusedVariables', 'mention in a comment is not a use', MentionInACommentIsNotAUse);
  RegisterTest('Linter.UnusedVariables', 'unused ones are reported individually', UnusedOnesAreReportedIndividually);
end.
