unit Test_Function_RandomInt;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;

procedure StaysInsideHalfOpenRange;
var I, V: Integer;
begin
  for I := 1 to 50 do
  begin
    V := StrToInt(EvalExpr('{{$randomInt 5 8}}'));
    AssertTrue((V >= 5) and (V < 8), 'value ' + IntToStr(V));
  end;
end;

procedure EmptyRangeIsReportedAndExpressionKept;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$randomInt 5 5}}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsStr('FunctionCall', P.Errors[0].Rule);
    AssertEqualsStr('{{$randomInt 5 5}}', P.HttpFile.Endpoints[0].RequestBody);
  finally P.Free; end;
end;

procedure NonNumericArgumentIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$randomInt a 5}}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
  finally P.Free; end;
end;

initialization
  RegisterTest('Function.RandomInt', 'stays inside [min, max)', StaysInsideHalfOpenRange);
  RegisterTest('Function.RandomInt', 'empty range is reported', EmptyRangeIsReportedAndExpressionKept);
  RegisterTest('Function.RandomInt', 'non numeric argument is reported', NonNumericArgumentIsReported);
end.
