unit Test_Function_Timestamp;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;
// fixed clock: 2026-10-19T12:00:00Z = 1792411200

procedure NowInSeconds;
begin
  AssertEqualsStr('1792411200', EvalExpr('{{$timestamp}}'));
end;

procedure NegativeDayOffset;
begin
  AssertEqualsStr('1792324800', EvalExpr('{{$timestamp -1 d}}'));
end;

procedure HourOffset;
begin
  AssertEqualsStr('1792418400', EvalExpr('{{$timestamp 2 h}}'));
end;

procedure YearOffset;
begin
  AssertEqualsStr('1823947200', EvalExpr('{{$timestamp 1 y}}'));
end;

procedure UnknownUnitIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$timestamp 1 q}}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
  finally P.Free; end;
end;

initialization
  RegisterTest('Function.Timestamp', 'now in seconds', NowInSeconds);
  RegisterTest('Function.Timestamp', 'negative day offset', NegativeDayOffset);
  RegisterTest('Function.Timestamp', 'hour offset', HourOffset);
  RegisterTest('Function.Timestamp', 'year offset', YearOffset);
  RegisterTest('Function.Timestamp', 'unknown unit is reported', UnknownUnitIsReported);
end.
