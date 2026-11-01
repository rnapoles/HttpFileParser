unit Test_Linter_Extension;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, TestLintHelpers, HttpFileParser, HttpFileAST, HttpFileLinter;

type
  { a rule written outside the unit: flags every request that has no headers }
  TNoHeadersRule = class(THttpLintRule)
  public
    function Id: string; override;
    procedure Check(AContext: THttpLintContext; ADiagnostics: THttpParseErrorList); override;
  end;

function TNoHeadersRule.Id: string;
begin
  Result := 'custom-no-headers';
end;

procedure TNoHeadersRule.Check(AContext: THttpLintContext; ADiagnostics: THttpParseErrorList);
var I: Integer;
begin
  for I := 0 to High(AContext.HttpFile.Endpoints) do
    if Length(AContext.HttpFile.Endpoints[I].RequestHeaders) = 0 then
      ADiagnostics.Add(hsWarning, AContext.HttpFile.Endpoints[I].Row, 1, 'no headers', 'x', Id);
end;

procedure CustomRuleRunsWithTheDefaultOnes;
var P: THttpFileParser; Linter: THttpFileLinter; L: THttpParseErrorList;
begin
  P := NewParser(Lines(['@unused = 1', 'GET http://x']));
  Linter := THttpFileLinter.Create(P.Functions, P.Scripting);
  L := THttpParseErrorList.Create;
  try
    Linter.AddRule(TNoHeadersRule.Create);
    AssertEqualsInt(5, Linter.RuleCount);
    Linter.Lint(P.HttpFile, L);
    AssertEqualsInt(1, CountRule(L, 'custom-no-headers'));
    AssertEqualsInt(1, CountRule(L, 'lint-unused-variable'));
  finally L.Free; Linter.Free; P.Free; end;
end;

procedure LinterWithoutDefaultRulesRunsOnlyWhatWasAdded;
var P: THttpFileParser; Linter: THttpFileLinter; L: THttpParseErrorList;
begin
  P := NewParser(Lines(['@unused = 1', 'GET http://x']));
  Linter := THttpFileLinter.Create(nil, nil, False);
  L := THttpParseErrorList.Create;
  try
    AssertEqualsInt(0, Linter.RuleCount);
    Linter.Lint(P.HttpFile, L);
    AssertEqualsInt(0, L.Count);
  finally L.Free; Linter.Free; P.Free; end;
end;

procedure DiagnosticsAreWarningsSortedByPosition;
var L: THttpParseErrorList; I: Integer;
begin
  L := LintSource(Lines(['GET http://x/{{zzz}}', '@unused = 1']));
  try
    AssertTrue(L.Count >= 2);
    AssertEqualsInt(0, L.ErrorCount);
    AssertEqualsInt(L.Count, L.WarningCount);
    for I := 1 to L.Count - 1 do
      AssertTrue(L[I - 1].Row <= L[I].Row);
  finally L.Free; end;
end;

initialization
  RegisterTest('Linter.Extension', 'custom rule runs with the default ones', CustomRuleRunsWithTheDefaultOnes);
  RegisterTest('Linter.Extension', 'linter without default rules runs only what was added', LinterWithoutDefaultRulesRunsOnlyWhatWasAdded);
  RegisterTest('Linter.Extension', 'diagnostics are warnings sorted by position', DiagnosticsAreWarningsSortedByPosition);
end.
