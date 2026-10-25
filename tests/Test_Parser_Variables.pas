unit Test_Parser_Variables;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

procedure ParsesNameAndValue;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@baseUrl = http://localhost:8443']));
  try
    AssertEqualsInt(1, Length(P.HttpFile.Variables));
    AssertEqualsStr('baseUrl', P.HttpFile.Variables[0].Name);
    AssertEqualsStr('http://localhost:8443', P.HttpFile.Variables[0].Value);
  finally P.Free; end;
end;

procedure ReplacesVariableReference;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@baseUrl = http://h', '@apiUrl = {{baseUrl}}/api/v1']));
  try
    AssertEqualsStr('{{baseUrl}}/api/v1', P.HttpFile.Variables[1].RawValue);
    AssertEqualsStr('http://h/api/v1', P.HttpFile.Variables[1].Value);
  finally P.Free; end;
end;

procedure RecordsRowAndColumn;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['', '  @a = 1']));
  try
    AssertEqualsInt(2, P.HttpFile.Variables[0].Row);
    AssertEqualsInt(3, P.HttpFile.Variables[0].Column);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.Variables', 'parses name and value', ParsesNameAndValue);
  RegisterTest('Parser.Variables', 'replaces variable references', ReplacesVariableReference);
  RegisterTest('Parser.Variables', 'records row and column', RecordsRowAndColumn);
end.
