unit Test_Parser_FileBody;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

procedure FileReferenceBecomesBodyFilePath;
var P: THttpFileParser; E: TEndpoint;
begin
  P := NewParser(Lines(['POST http://x', '', '< ./payload.xml # only valid here']));
  try
    E := P.HttpFile.Endpoints[0];
    AssertEqualsStr('./payload.xml', E.BodyFilePath);
    AssertEqualsStr('', E.RequestBody);
    AssertEqualsInt(0, P.Errors.Count);
  finally P.Free; end;
end;

procedure FileReferenceReplacesVariables;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@d = data', 'POST http://x', '', '< ./{{d}}.xml']));
  try
    AssertEqualsStr('./data.xml', P.HttpFile.Endpoints[0].BodyFilePath);
  finally P.Free; end;
end;

procedure FileReferenceFollowedByNextRequest;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '< ./a.xml', '', '# @name two', 'GET http://y']));
  try
    AssertEqualsInt(2, Length(P.HttpFile.Endpoints));
    AssertEqualsStr('./a.xml', P.HttpFile.Endpoints[0].BodyFilePath);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.FileBody', 'file reference becomes BodyFilePath', FileReferenceBecomesBodyFilePath);
  RegisterTest('Parser.FileBody', 'file reference replaces variables', FileReferenceReplacesVariables);
  RegisterTest('Parser.FileBody', 'file reference followed by next request', FileReferenceFollowedByNextRequest);
end.
