unit Test_Function_LocalDateTime;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;
// fixed clock 12:00 UTC, local offset UTC-06:00

procedure CustomFormatUsesLocalTime;
begin
  AssertEqualsStr('06:00 -06:00', EvalExpr('{{$localDatetime ''HH:mm Z''}}', -360));
end;

procedure Rfc1123UsesNumericOffset;
begin
  AssertEqualsStr('Mon, 19 Oct 2026 06:00:00 -0600', EvalExpr('{{$localDatetime rfc1123}}', -360));
end;

procedure Iso8601UsesNumericOffset;
begin
  AssertEqualsStr('2026-10-19T06:00:00.000-06:00', EvalExpr('{{$localDatetime iso8601}}', -360));
end;

initialization
  RegisterTest('Function.LocalDateTime', 'custom format uses local time', CustomFormatUsesLocalTime);
  RegisterTest('Function.LocalDateTime', 'rfc1123 uses numeric offset', Rfc1123UsesNumericOffset);
  RegisterTest('Function.LocalDateTime', 'iso8601 uses numeric offset', Iso8601UsesNumericOffset);
end.
