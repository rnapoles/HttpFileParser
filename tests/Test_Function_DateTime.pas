unit Test_Function_DateTime;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;
// fixed clock: Monday 2026-10-19 12:00:00 UTC

procedure Rfc1123;
begin
  AssertEqualsStr('Mon, 19 Oct 2026 12:00:00 GMT', EvalExpr('{{$datetime rfc1123}}'));
end;

procedure Iso8601;
begin
  AssertEqualsStr('2026-10-19T12:00:00.000Z', EvalExpr('{{$datetime iso8601}}'));
end;

procedure SingleQuotedCustomFormat;
begin
  AssertEqualsStr('2026-10-19', EvalExpr('{{$datetime ''YYYY-MM-DD''}}'));
end;

procedure DoubleQuotedFormatWithYearOffset;
begin
  AssertEqualsStr('19-10-2027', EvalExpr('{{$datetime "DD-MM-YYYY" 1 y}}'));
end;

procedure MonthOffsetOnIso8601;
begin
  AssertEqualsStr('2026-09-19T12:00:00.000Z', EvalExpr('{{$datetime iso8601 -1 M}}'));
end;

initialization
  RegisterTest('Function.DateTime', 'rfc1123', Rfc1123);
  RegisterTest('Function.DateTime', 'iso8601', Iso8601);
  RegisterTest('Function.DateTime', 'single quoted custom format', SingleQuotedCustomFormat);
  RegisterTest('Function.DateTime', 'double quoted format with year offset', DoubleQuotedFormatWithYearOffset);
  RegisterTest('Function.DateTime', 'month offset on iso8601', MonthOffsetOnIso8601);
end.
