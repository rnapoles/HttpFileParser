unit Test_Parser_JsonPathVariables;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

procedure JsonPathValueStaysRaw;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@t = {{$jsonpath ''login.response.body.$.id''}}']));
  try
    AssertEqualsStr('{{$jsonpath ''login.response.body.$.id''}}', P.HttpFile.Variables[0].Value);
    AssertEqualsInt(0, P.Errors.Count);
  finally P.Free; end;
end;

procedure ReferencingJsonPathVariableKeepsRawText;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@t = {{$jsonpath ''a.b''}}', '@u = Bearer {{t}}']));
  try
    AssertEqualsStr('Bearer {{$jsonpath ''a.b''}}', P.HttpFile.Variables[1].Value);
  finally P.Free; end;
end;

procedure XPathValueStaysRaw;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@x = {{$xpath ''//a''}}']));
  try
    AssertEqualsStr('{{$xpath ''//a''}}', P.HttpFile.Variables[0].Value);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.JsonPathVariables', 'jsonpath value stays raw', JsonPathValueStaysRaw);
  RegisterTest('Parser.JsonPathVariables', 'reference to jsonpath variable keeps raw text', ReferencingJsonPathVariableKeepsRawText);
  RegisterTest('Parser.JsonPathVariables', 'xpath value stays raw', XPathValueStaysRaw);
end.
