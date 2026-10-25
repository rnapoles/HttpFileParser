unit Test_Parser_Headers;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

procedure ParsesHeadersAndReplacesVariables;
var P: THttpFileParser; E: TEndpoint;
begin
  P := NewParser(Lines(['@t = tok', 'GET http://x', 'Authorization: Bearer {{t}}', 'Accept:text/plain']));
  try
    E := P.HttpFile.Endpoints[0];
    AssertEqualsInt(2, Length(E.RequestHeaders));
    AssertEqualsStr('Authorization', E.RequestHeaders[0].Name);
    AssertEqualsStr('Bearer tok', E.RequestHeaders[0].Value);
    AssertEqualsStr('Bearer {{t}}', E.RequestHeaders[0].RawValue);
    AssertEqualsStr('text/plain', E.RequestHeaders[1].Value);
  finally P.Free; end;
end;

procedure CommentsBetweenHeadersAreSkipped;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['GET http://x', '# comment', 'Accept: a']));
  try
    AssertEqualsInt(1, Length(P.HttpFile.Endpoints[0].RequestHeaders));
  finally P.Free; end;
end;

procedure FindRequestHeaderIgnoresCase;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['GET http://x', 'Content-Type: a/b']));
  try
    AssertTrue(P.HttpFile.Endpoints[0].FindRequestHeader('content-type') <> nil);
  finally P.Free; end;
end;

procedure HeaderRecordsPosition;
var P: THttpFileParser; H: TRequestHeader;
begin
  P := NewParser(Lines(['GET http://x', 'Accept: a']));
  try
    H := P.HttpFile.Endpoints[0].RequestHeaders[0];
    AssertEqualsInt(2, H.Row);
    AssertEqualsInt(1, H.Column);
    AssertEqualsInt(9, H.ValueColumn);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.Headers', 'parses headers and replaces variables', ParsesHeadersAndReplacesVariables);
  RegisterTest('Parser.Headers', 'comments between headers are skipped', CommentsBetweenHeadersAreSkipped);
  RegisterTest('Parser.Headers', 'FindRequestHeader ignores case', FindRequestHeaderIgnoresCase);
  RegisterTest('Parser.Headers', 'header records position', HeaderRecordsPosition);
end.
