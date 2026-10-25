unit Test_Lexer_FileRefAndScriptKinds;
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

procedure FileReference;
begin
  AssertTrue(Tok('< ./a.json').Kind = tkFileRef);
  AssertEqualsStr('./a.json', Tok('< ./a.json').Value);
end;

procedure FileReferenceDropsTrailingComment;
begin
  AssertEqualsStr('C:\d\x.xml', Tok('< C:\d\x.xml # note').Value);
end;

procedure PreRequestScript;
begin
  AssertTrue(Tok('< {% client.log(1) %}').Kind = tkScript);
end;

procedure ResponseHandlerScript;
begin
  AssertTrue(Tok('> {% client.log(1) %}').Kind = tkScript);
end;

procedure XmlLineIsText;
begin
  AssertTrue(Tok('<root>').Kind = tkText);
end;

initialization
  RegisterTest('Lexer.FileRefScript', 'file reference', FileReference);
  RegisterTest('Lexer.FileRefScript', 'file reference drops trailing comment', FileReferenceDropsTrailingComment);
  RegisterTest('Lexer.FileRefScript', 'pre-request script marker', PreRequestScript);
  RegisterTest('Lexer.FileRefScript', 'response handler script marker', ResponseHandlerScript);
  RegisterTest('Lexer.FileRefScript', 'XML line is text', XmlLineIsText);
end.
