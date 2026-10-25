unit Test_Parser_RequestLine;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

function First(P: THttpFileParser): TEndpoint;
begin
  Result := P.HttpFile.Endpoints[0];
end;

procedure ParsesVerbUrlAndRevision;
var P: THttpFileParser;
begin
  P := NewParser('GET http://x/a HTTP/1.0');
  try
    AssertEqualsStr('GET', First(P).Verb);
    AssertEqualsStr('http://x/a', First(P).Url);
    AssertEqualsStr('HTTP/1.0', First(P).HttpRevision);
  finally P.Free; end;
end;

procedure RevisionDefaultsToHttp11;
var P: THttpFileParser;
begin
  P := NewParser('POST http://x');
  try
    AssertEqualsStr('HTTP/1.1', First(P).HttpRevision);
  finally P.Free; end;
end;

procedure BareUrlIsGet;
var P: THttpFileParser;
begin
  P := NewParser('http://x/y');
  try
    AssertEqualsStr('GET', First(P).Verb);
  finally P.Free; end;
end;

procedure QueryContinuationLinesAreAppended;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['GET http://x/a', '  ?page=1', '  &size=2']));
  try
    AssertEqualsStr('http://x/a?page=1&size=2', First(P).Url);
  finally P.Free; end;
end;

procedure UrlReplacesVariablesButRawUrlDoesNot;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@h = http://z', 'GET {{h}}/p']));
  try
    AssertEqualsStr('http://z/p', First(P).Url);
    AssertEqualsStr('{{h}}/p', First(P).RawUrl);
  finally P.Free; end;
end;

procedure RecordsRowAndColumn;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['', '  GET http://x']));
  try
    AssertEqualsInt(2, First(P).Row);
    AssertEqualsInt(3, First(P).Column);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.RequestLine', 'verb, url and revision', ParsesVerbUrlAndRevision);
  RegisterTest('Parser.RequestLine', 'revision defaults to HTTP/1.1', RevisionDefaultsToHttp11);
  RegisterTest('Parser.RequestLine', 'bare URL is GET', BareUrlIsGet);
  RegisterTest('Parser.RequestLine', 'query continuation lines are appended', QueryContinuationLinesAreAppended);
  RegisterTest('Parser.RequestLine', 'Url is replaced, RawUrl is not', UrlReplacesVariablesButRawUrlDoesNot);
  RegisterTest('Parser.RequestLine', 'records row and column', RecordsRowAndColumn);
end.
