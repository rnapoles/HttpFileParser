unit Test_Linter_Circular;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, TestLintHelpers, HttpFileParser, HttpFileAST, HttpFileLinter;

const Rule = 'lint-circular-reference';

function Cycles(const ASource: string; out AMessage: string; out ARow, AColumn: Integer): Integer;
var L: THttpParseErrorList; I: Integer;
begin
  L := LintSource(ASource);
  try
    Result := CountRule(L, Rule);
    AMessage := '';
    ARow := 0;
    AColumn := 0;
    I := IndexOfRule(L, Rule);
    if I >= 0 then
    begin
      AMessage := L[I].Message;
      ARow := L[I].Row;
      AColumn := L[I].Column;
    end;
  finally L.Free; end;
end;

procedure VariablesThatReferToEachOtherAreOneCycle;
var M: string; R, C: Integer;
begin
  AssertEqualsInt(1, Cycles(Lines(['@a = {{b}}', '@b = {{a}}', 'GET http://x/{{a}}']), M, R, C));
  AssertEqualsInt(1, R);
  AssertEqualsInt(1, C);
  AssertTrue(Pos('@a -> @b -> @a', M) > 0, M);
end;

procedure SelfReferenceIsACycle;
var M: string; R, C: Integer;
begin
  AssertEqualsInt(1, Cycles(Lines(['@a = {{a}}']), M, R, C));
end;

procedure RequestsThatReadEachOthersBodiesAreACycle;
var M: string; R, C: Integer;
begin
  AssertEqualsInt(1, Cycles(Lines(['# @name a', 'POST http://x', '', '{{b.request.body.*}}', '',
    '# @name b', 'POST http://y', '', '{{a.request.body.*}}']), M, R, C));
  AssertEqualsInt(2, R); // reported at the request line of "a"
  AssertTrue(Pos('request "a" -> request "b" -> request "a"', M) > 0, M);
end;

procedure DependencyThroughAVariableAndAResponseIsACycle;
var M: string; R, C: Integer;
begin
  // login needs t, t needs the response of login
  AssertEqualsInt(1, Cycles(Lines(['@t = {{login.response.headers.X}}', '# @name login', 'GET http://x',
    'Authorization: {{t}}']), M, R, C));
end;

procedure NormalChainingIsNotACycle;
var M: string; R, C: Integer;
begin
  AssertEqualsInt(0, Cycles(Lines(['@t = {{login.response.headers.X}}', '# @name login', 'POST http://x', '',
    '# @name getUser', 'GET http://y', 'Authorization: {{t}}']), M, R, C));
end;

procedure ACycleIsReportedOnce;
var M: string; R, C: Integer;
begin
  AssertEqualsInt(1, Cycles(Lines(['@a = {{b}}', '@b = {{c}}', '@c = {{a}}',
    'GET http://x/{{a}}/{{b}}/{{c}}']), M, R, C));
end;

initialization
  RegisterTest('Linter.Circular', 'variables that refer to each other are one cycle', VariablesThatReferToEachOtherAreOneCycle);
  RegisterTest('Linter.Circular', 'self reference is a cycle', SelfReferenceIsACycle);
  RegisterTest('Linter.Circular', 'requests that read each other are a cycle', RequestsThatReadEachOthersBodiesAreACycle);
  RegisterTest('Linter.Circular', 'dependency through a variable and a response is a cycle', DependencyThroughAVariableAndAResponseIsACycle);
  RegisterTest('Linter.Circular', 'normal chaining is not a cycle', NormalChainingIsNotACycle);
  RegisterTest('Linter.Circular', 'a cycle is reported once', ACycleIsReportedOnce);
end.
