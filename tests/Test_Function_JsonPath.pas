unit Test_Function_JsonPath;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;

procedure ReturnsEmptyStringInRequests;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', 'a{{$jsonpath ''r.response.body.$.id''}}b']));
  try
    AssertEqualsStr('ab', P.HttpFile.Endpoints[0].RequestBody);
    AssertEqualsInt(0, P.Errors.Count);
  finally P.Free; end;
end;

procedure RequiresAnArgument;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$jsonpath}}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
  finally P.Free; end;
end;

initialization
  RegisterTest('Function.JsonPath', 'returns empty string in requests', ReturnsEmptyStringInRequests);
  RegisterTest('Function.JsonPath', 'requires an argument', RequiresAnArgument);
end.
