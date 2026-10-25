unit Test_Parser_ScriptsRejected;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

procedure PreRequestScriptIsAnError;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['< {% client.log(1) %}', 'GET http://x']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsStr('Script', P.Errors[0].Rule);
    AssertEqualsInt(1, Length(P.HttpFile.Endpoints));
  finally P.Free; end;
end;

procedure MultiLineScriptInsideBodyIsSkipped;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{}', '', '< {%', '  client.log(1)', '%}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsInt(5, P.Errors[0].Row);
    AssertEqualsStr('{}', P.HttpFile.Endpoints[0].RequestBody);
  finally P.Free; end;
end;

procedure ResponseHandlerIsAnError;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['GET http://x', '', '> {% client.log(1) %}']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsStr('Script', P.Errors[0].Rule);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.ScriptsRejected', 'pre-request script is an error', PreRequestScriptIsAnError);
  RegisterTest('Parser.ScriptsRejected', 'multi-line script inside body is skipped', MultiLineScriptInsideBodyIsSkipped);
  RegisterTest('Parser.ScriptsRejected', 'response handler is an error', ResponseHandlerIsAnError);
end.
