unit Test_Lexer_Primitives;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses MiniTest, HttpFileLexer;

procedure PeekDoesNotConsume;
var L: THttpFileLexer;
begin
  L := THttpFileLexer.Create('ab');
  try
    AssertEqualsStr('a', L.PeekChar);
    AssertEqualsStr('a', L.PeekChar);
    AssertEqualsStr('b', L.PeekChar(1));
    AssertEqualsInt(1, L.Col);
  finally L.Free; end;
end;

procedure PeekPastEndReturnsNul;
var L: THttpFileLexer;
begin
  L := THttpFileLexer.Create('');
  try
    AssertTrue(L.PeekChar = #0);
    AssertTrue(L.AtEnd);
  finally L.Free; end;
end;

procedure ConsumeTracksRowAndColumnAcrossCrLf;
var L: THttpFileLexer;
begin
  L := THttpFileLexer.Create('a'#13#10'b');
  try
    L.ConsumeChar;
    AssertEqualsInt(2, L.Col);
    AssertTrue(L.ConsumeChar = #10, 'CRLF is one #10');
    AssertEqualsInt(2, L.Row);
    AssertEqualsInt(1, L.Col);
    AssertEqualsInt(4, L.Position);
  finally L.Free; end;
end;

procedure MatchTokenConsumesOnlyOnMatch;
var L: THttpFileLexer;
begin
  L := THttpFileLexer.Create('GET x');
  try
    AssertTrue(not L.MatchToken('POST'));
    AssertEqualsInt(1, L.Col);
    AssertTrue(L.MatchToken('GET'));
    AssertEqualsInt(4, L.Col);
  finally L.Free; end;
end;

initialization
  RegisterTest('Lexer.Primitives', 'PeekChar does not consume', PeekDoesNotConsume);
  RegisterTest('Lexer.Primitives', 'PeekChar past end returns NUL', PeekPastEndReturnsNul);
  RegisterTest('Lexer.Primitives', 'ConsumeChar tracks row/column across CRLF', ConsumeTracksRowAndColumnAcrossCrLf);
  RegisterTest('Lexer.Primitives', 'MatchToken consumes only on match', MatchTokenConsumesOnlyOnMatch);
end.
