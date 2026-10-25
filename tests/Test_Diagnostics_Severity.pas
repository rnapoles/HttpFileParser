unit Test_Diagnostics_Severity;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST;

procedure ScriptIsAWarning;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['< {% client.log(1) %}', 'GET http://x']));
  try
    AssertEqualsInt(0, P.Errors.ErrorCount);
    AssertEqualsInt(1, P.Errors.WarningCount);
    AssertTrue(P.Errors[0].Severity = hsWarning);
    AssertEqualsStr('Script', P.Errors[0].Rule);
  finally P.Free; end;
end;

procedure UnresolvedPlaceholderIsAWarningWithRange;
var P: THttpFileParser;
begin
  P := NewParser('GET http://{{host}}/x');
  try
    AssertEqualsInt(0, P.Errors.ErrorCount);
    AssertEqualsInt(1, P.Errors.WarningCount);
    AssertEqualsStr('Placeholder', P.Errors[0].Rule);
    AssertEqualsInt(1, P.Errors[0].Row);
    AssertEqualsInt(12, P.Errors[0].Column);
    AssertEqualsInt(1, P.Errors[0].EndRow);
    AssertEqualsInt(20, P.Errors[0].EndColumn);
    AssertTrue(P.Errors.HasErrors = False);
  finally P.Free; end;
end;

procedure SyntaxProblemIsAnErrorWithRange;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@a = 1', 'junk']));
  try
    AssertEqualsInt(1, P.Errors.ErrorCount);
    AssertTrue(P.Errors.HasErrors);
    AssertEqualsInt(2, P.Errors[0].Row);
    AssertEqualsInt(1, P.Errors[0].Column);
    AssertEqualsInt(2, P.Errors[0].EndRow);
    AssertEqualsInt(5, P.Errors[0].EndColumn);
  finally P.Free; end;
end;

procedure MissingUrlIsZeroWidth;
var P: THttpFileParser;
begin
  P := NewParser('GET');
  try
    AssertEqualsInt(4, P.Errors[0].Column);
    AssertEqualsInt(4, P.Errors[0].EndColumn);
  finally P.Free; end;
end;

procedure FunctionErrorCoversTheExpression;
var P: THttpFileParser;
begin
  P := NewParser('@a = x {{$nope 1}}');
  try
    AssertTrue(P.Errors[0].Severity = hsError);
    AssertEqualsInt(8, P.Errors[0].Column);
    AssertEqualsInt(19, P.Errors[0].EndColumn); // after the closing braces
  finally P.Free; end;
end;

procedure TokenSpanningLinesEndsOnTheLastLine;
var L: THttpParseErrorList;
begin
  L := THttpParseErrorList.Create;
  try
    L.Add(hsError, 1, 1, 'm', 'ab'#10'cd', 'r');
    AssertEqualsInt(2, L[0].EndRow);
    AssertEqualsInt(3, L[0].EndColumn);
  finally L.Free; end;
end;

procedure CountsAndFormattingUseSeverity;
var L: THttpParseErrorList;
begin
  L := THttpParseErrorList.Create;
  try
    L.Add(1, 1, 'e', 'x', 'r');
    L.Add(hsWarning, 2, 1, 'w', 'x', 'r');
    L.Add(hsInfo, 3, 1, 'i', 'x', 'r');
    AssertEqualsInt(3, L.Count);
    AssertEqualsInt(1, L.ErrorCount);
    AssertEqualsInt(1, L.WarningCount);
    AssertEqualsInt(1, L.InfoCount);
    AssertTrue(Pos('warning:', FormatParseError(L[1])) = 1);
    AssertTrue(Pos('error:', FormatParseError(L[0])) = 1);
  finally L.Free; end;
end;

initialization
  RegisterTest('Diagnostics.Severity', 'script is a warning', ScriptIsAWarning);
  RegisterTest('Diagnostics.Severity', 'unresolved placeholder is a warning with range', UnresolvedPlaceholderIsAWarningWithRange);
  RegisterTest('Diagnostics.Severity', 'syntax problem is an error with range', SyntaxProblemIsAnErrorWithRange);
  RegisterTest('Diagnostics.Severity', 'missing URL is zero-width', MissingUrlIsZeroWidth);
  RegisterTest('Diagnostics.Severity', 'function error covers the expression', FunctionErrorCoversTheExpression);
  RegisterTest('Diagnostics.Severity', 'token spanning lines ends on the last line', TokenSpanningLinesEndsOnTheLastLine);
  RegisterTest('Diagnostics.Severity', 'counts and formatting use severity', CountsAndFormattingUseSeverity);
end.
