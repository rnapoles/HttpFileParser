unit Test_Lexer_RequestLineKinds;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses MiniTest, HttpFileLexer;

function Tok(const S: string): THttpToken;
var L: THttpFileLexer;
begin
  L := THttpFileLexer.Create(S);
  try Result := L.NextToken; finally L.Free; end;
end;

procedure VerbUrlAndVersion;
var T: THttpToken;
begin
  T := Tok('POST /a HTTP/2');
  AssertTrue(T.Kind = tkRequestLine);
  AssertEqualsStr('POST', T.Name);
  AssertEqualsStr('/a', T.Value);
  AssertEqualsStr('HTTP/2', T.Version);
end;

procedure UrlOnlyDefaultsToGet;
begin
  AssertEqualsStr('GET', Tok('https://x/y').Name);
  AssertEqualsStr('https://x/y', Tok('https://x/y').Value);
end;

procedure LowerCaseVerbIsNotARequest;
begin
  AssertTrue(Tok('get /a').Kind <> tkRequestLine);
end;

procedure IndentedQueryIsContinuation;
begin
  AssertTrue(Tok('  ?a=1').Kind = tkQueryContinuation);
  AssertEqualsStr('&b=2', Tok(#9'&b=2').Value);
end;

initialization
  RegisterTest('Lexer.RequestLine', 'verb, url and version', VerbUrlAndVersion);
  RegisterTest('Lexer.RequestLine', 'bare URL defaults to GET', UrlOnlyDefaultsToGet);
  RegisterTest('Lexer.RequestLine', 'lower case verb is not a request line', LowerCaseVerbIsNotARequest);
  RegisterTest('Lexer.RequestLine', 'indented ?/& line is a continuation', IndentedQueryIsContinuation);
end.
