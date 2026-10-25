unit Test_Function_UnknownFunction;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;

procedure ReportsPositionOfExpression;
var P: THttpFileParser;
begin
  P := NewParser('@a = x {{$nope 1}}');
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsInt(1, P.Errors[0].Row);
    AssertEqualsInt(8, P.Errors[0].Column);
    AssertEqualsStr('FunctionCall', P.Errors[0].Rule);
  finally P.Free; end;
end;

procedure LeavesExpressionUntouched;
var P: THttpFileParser;
begin
  P := NewParser('@a = x {{$nope 1}}');
  try
    AssertEqualsStr('x {{$nope 1}}', P.HttpFile.Variables[0].Value);
  finally P.Free; end;
end;

procedure ReportsRowInsideMultiLineBody;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', 'line1', '  {{$nope}}']));
  try
    AssertEqualsInt(4, P.Errors[0].Row);
    AssertEqualsInt(3, P.Errors[0].Column);
  finally P.Free; end;
end;

initialization
  RegisterTest('Function.Unknown', 'reports position of expression', ReportsPositionOfExpression);
  RegisterTest('Function.Unknown', 'leaves expression untouched', LeavesExpressionUntouched);
  RegisterTest('Function.Unknown', 'reports row inside multi-line body', ReportsRowInsideMultiLineBody);
end.
