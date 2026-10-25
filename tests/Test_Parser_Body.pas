unit Test_Parser_Body;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

function Ep(P: THttpFileParser; I: Integer): TEndpoint;
begin
  Result := P.HttpFile.Endpoints[I];
end;

procedure ParsesMultiLineBody;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', 'Content-Type: application/json', '', '{', '  "a": 1', '}']));
  try
    AssertEqualsStr('{'#10'  "a": 1'#10'}', Ep(P, 0).RequestBody);
    AssertEqualsInt(4, Ep(P, 0).BodyRow);
  finally P.Free; end;
end;

procedure ReplacesVariablesButKeepsRawBody;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@n = Bob', 'POST http://x', '', 'hello {{n}}']));
  try
    AssertEqualsStr('hello Bob', Ep(P, 0).RequestBody);
    AssertEqualsStr('hello {{n}}', Ep(P, 0).RawRequestBody);
  finally P.Free; end;
end;

procedure RequestWithoutBodyHasEmptyBody;
var P: THttpFileParser;
begin
  P := NewParser('GET http://a');
  try
    AssertEqualsStr('', Ep(P, 0).RequestBody);
  finally P.Free; end;
end;

procedure BodyEndsAtSeparator;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://a', '', 'one', '', '###', 'GET http://b']));
  try
    AssertEqualsInt(2, Length(P.HttpFile.Endpoints));
    AssertEqualsStr('one', Ep(P, 0).RequestBody);
  finally P.Free; end;
end;

procedure BodyEndsAtRequestLineAfterBlankLine;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://a', '', 'one', '', 'GET http://b']));
  try
    AssertEqualsInt(2, Length(P.HttpFile.Endpoints));
    AssertEqualsStr('one', Ep(P, 0).RequestBody);
  finally P.Free; end;
end;

procedure BodyEndsAtNameMetadata;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://a', '', 'one', '', '# @name second', 'GET http://b']));
  try
    AssertEqualsStr('one', Ep(P, 0).RequestBody);
    AssertEqualsStr('second', Ep(P, 1).Name);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.Body', 'parses multi-line body', ParsesMultiLineBody);
  RegisterTest('Parser.Body', 'replaces variables but keeps raw body', ReplacesVariablesButKeepsRawBody);
  RegisterTest('Parser.Body', 'request without body has empty body', RequestWithoutBodyHasEmptyBody);
  RegisterTest('Parser.Body', 'body ends at ### separator', BodyEndsAtSeparator);
  RegisterTest('Parser.Body', 'body ends at request line after blank line', BodyEndsAtRequestLineAfterBlankLine);
  RegisterTest('Parser.Body', 'body ends at @name metadata', BodyEndsAtNameMetadata);
end.
