unit Test_Parser_VariableReferences;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

procedure ForwardReferenceIsResolved;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@a = {{b}}x', '@b = 1']));
  try
    AssertEqualsStr('1x', P.HttpFile.Variables[0].Value);
  finally P.Free; end;
end;

procedure UnknownReferenceIsLeftUntouched;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@a = {{host}}/x']));
  try
    AssertEqualsStr('{{host}}/x', P.HttpFile.Variables[0].Value);
    AssertEqualsInt(0, P.Errors.Count);
  finally P.Free; end;
end;

procedure CircularReferenceIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@a = {{b}}', '@b = {{a}}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsStr('VariableReference', P.Errors[0].Rule);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.VariableReferences', 'forward reference is resolved', ForwardReferenceIsResolved);
  RegisterTest('Parser.VariableReferences', 'unknown reference is left untouched', UnknownReferenceIsLeftUntouched);
  RegisterTest('Parser.VariableReferences', 'circular reference is reported', CircularReferenceIsReported);
end.
