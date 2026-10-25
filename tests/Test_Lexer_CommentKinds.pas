unit Test_Lexer_CommentKinds;
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

procedure SeparatorKeepsTitle;
begin
  AssertTrue(Tok('### My title').Kind = tkSeparator);
  AssertEqualsStr('My title', Tok('### My title').Value);
end;

procedure HashAndSlashesAreComments;
begin
  AssertTrue(Tok('# note').Kind = tkComment);
  AssertTrue(Tok('// note').Kind = tkComment);
end;

procedure NameMetadataWithEquals;
begin
  AssertTrue(Tok('# @name = hello').Kind = tkMetaName);
  AssertEqualsStr('hello', Tok('# @name = hello').Name);
end;

procedure NameMetadataWithoutEquals;
begin
  AssertEqualsStr('loginRequest', Tok('// @name loginRequest').Name);
end;

procedure BlankLineIsBlank;
begin
  AssertTrue(Tok('   ').Kind = tkBlank);
end;

initialization
  RegisterTest('Lexer.Comments', 'separator keeps its title', SeparatorKeepsTitle);
  RegisterTest('Lexer.Comments', '# and // are comments', HashAndSlashesAreComments);
  RegisterTest('Lexer.Comments', '@name with equals sign', NameMetadataWithEquals);
  RegisterTest('Lexer.Comments', '@name without equals sign', NameMetadataWithoutEquals);
  RegisterTest('Lexer.Comments', 'whitespace-only line is blank', BlankLineIsBlank);
end.
