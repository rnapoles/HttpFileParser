unit Test_Lexer_VariableAndHeaderKinds;
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

procedure VariableDeclaration;
var T: THttpToken;
begin
  T := Tok('@baseUrl = http://x');
  AssertTrue(T.Kind = tkVariableDecl);
  AssertEqualsStr('baseUrl', T.Name);
  AssertEqualsStr('http://x', T.Value);
  AssertEqualsInt(12, T.ValueCol);
end;

procedure AtSignWithoutEqualsIsText;
begin
  AssertTrue(Tok('@oops').Kind = tkText);
end;

procedure HeaderLine;
var T: THttpToken;
begin
  T := Tok('Accept:  text/html ');
  AssertTrue(T.Kind = tkHeaderLine);
  AssertEqualsStr('Accept', T.Name);
  AssertEqualsStr('text/html', T.Value);
end;

procedure JsonLineIsNotAHeader;
begin
  AssertTrue(Tok('  "a": 1').Kind = tkText);
end;

initialization
  RegisterTest('Lexer.VariablesHeaders', 'variable declaration', VariableDeclaration);
  RegisterTest('Lexer.VariablesHeaders', '@name without = is text', AtSignWithoutEqualsIsText);
  RegisterTest('Lexer.VariablesHeaders', 'header line', HeaderLine);
  RegisterTest('Lexer.VariablesHeaders', 'JSON line is not a header', JsonLineIsNotAHeader);
end.
