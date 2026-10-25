unit Test_Function_Guid;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;

procedure HasUuidShape;
var V: string;
begin
  V := EvalExpr('{{$guid}}');
  AssertEqualsInt(36, Length(V));
  AssertTrue((V[9] = '-') and (V[14] = '-') and (V[19] = '-') and (V[24] = '-'));
end;

procedure IsVersion4WithRfc4122Variant;
var V: string;
begin
  V := EvalExpr('{{$guid}}');
  AssertEqualsStr('4', V[15]);
  AssertTrue(Pos(V[20], '89ab') > 0, 'variant nibble');
end;

procedure ConsecutiveValuesDiffer;
begin
  AssertTrue(EvalExpr('{{$guid}}') <> EvalExpr('{{$guid}}'));
end;

initialization
  RegisterTest('Function.Guid', 'has UUID shape', HasUuidShape);
  RegisterTest('Function.Guid', 'is version 4 with RFC 4122 variant', IsVersion4WithRfc4122Variant);
  RegisterTest('Function.Guid', 'consecutive values differ', ConsecutiveValuesDiffer);
end.
