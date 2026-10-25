unit Test_Generator_Curl;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, CodeGenerator, CurlGenerator, PostmanCollectionGenerator, JsonWriter;

function Convert(const ASource: string; AMultiline: Boolean; out AWarnings: Integer): string;
var P: THttpFileParser; G: TCurlGenerator;
begin
  P := NewParser(ASource);
  G := TCurlGenerator.Create;
  try
    G.Multiline := AMultiline;
    G.IncludeComments := False;
    Result := G.Generate(P.HttpFile)[0].Content;
    AWarnings := G.Warnings.Count;
  finally G.Free; P.Free; end;
end;

procedure PlainGetHasNoMethodFlag;
var W: Integer;
begin
  AssertEqualsStr('curl ''http://x/a'''#10, Convert('GET http://x/a', False, W));
end;

procedure PostWithHeaderAndBody;
var W: Integer;
begin
  AssertEqualsStr('curl -X POST ''http://x'' -H ''A: b'' --data-raw ''{"a":1}'''#10,
    Convert(Lines(['POST http://x', 'A: b', '', '{"a":1}']), False, W));
end;

procedure MultilineJoinsWithBackslash;
var W: Integer;
begin
  AssertEqualsStr('curl \'#10'  -X DELETE \'#10'  ''http://x'''#10, Convert('DELETE http://x', True, W));
end;

procedure SingleQuotesAreEscaped;
begin
  AssertEqualsStr('''it''\''''s''', ShellQuote('it''s'));
end;

procedure FileBodyUsesDataBinary;
var W: Integer;
begin
  AssertEqualsStr('curl -X POST ''http://x'' --data-binary ''@./a.xml'''#10,
    Convert(Lines(['POST http://x', '', '< ./a.xml']), False, W));
end;

procedure UnresolvedPlaceholderIsWarned;
var W: Integer;
begin
  Convert('GET http://{{host}}/x', False, W);
  AssertEqualsInt(1, W);
end;

procedure GeneratesSingleShellFile;
var P: THttpFileParser; G: TCurlGenerator;
begin
  P := NewParser('GET http://x');
  G := TCurlGenerator.Create;
  try
    AssertEqualsInt(1, Length(G.Generate(P.HttpFile, 'my api')));
    AssertEqualsStr('my api.sh', G.Generate(P.HttpFile, 'my api')[0].FileName);
  finally G.Free; P.Free; end;
end;

initialization
  RegisterTest('Generator.Curl', 'plain GET has no method flag', PlainGetHasNoMethodFlag);
  RegisterTest('Generator.Curl', 'POST with header and body', PostWithHeaderAndBody);
  RegisterTest('Generator.Curl', 'multiline joins with backslash', MultilineJoinsWithBackslash);
  RegisterTest('Generator.Curl', 'single quotes are escaped', SingleQuotesAreEscaped);
  RegisterTest('Generator.Curl', 'file body uses --data-binary', FileBodyUsesDataBinary);
  RegisterTest('Generator.Curl', 'unresolved placeholder is warned', UnresolvedPlaceholderIsWarned);
  RegisterTest('Generator.Curl', 'generates a single .sh file', GeneratesSingleShellFile);
end.
