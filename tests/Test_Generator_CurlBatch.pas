unit Test_Generator_CurlBatch;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, CodeGenerator, CurlGenerator;

const
  Header = '@echo off'#13#10#13#10;

function Convert(const ASource: string; AMultiline, AComments: Boolean): TGeneratedFileArray;
var P: THttpFileParser; G: TCurlGenerator;
begin
  P := NewParser(ASource);
  G := TCurlGenerator.Create;
  try
    G.Target := ctWindowsBatch;
    G.Multiline := AMultiline;
    G.IncludeComments := AComments;
    Result := G.Generate(P.HttpFile);
  finally G.Free; P.Free; end;
end;

procedure UsesBatExtensionAndPreamble;
var F: TGeneratedFileArray;
begin
  F := Convert('GET http://x/a', False, False);
  AssertEqualsStr('requests.bat', F[0].FileName);
  AssertEqualsStr(Header + 'curl "http://x/a"'#13#10, F[0].Content);
end;

procedure DefaultTargetIsShell;
var P: THttpFileParser; G: TCurlGenerator;
begin
  P := NewParser('GET http://x');
  G := TCurlGenerator.Create;
  try AssertEqualsStr('requests.sh', G.Generate(P.HttpFile)[0].FileName); finally G.Free; P.Free; end;
end;

procedure MultilineUsesCaretAndCrLf;
begin
  AssertEqualsStr(Header + 'curl ^'#13#10'  -X DELETE ^'#13#10'  "http://x"'#13#10,
    Convert('DELETE http://x', True, False)[0].Content);
end;

procedure QuoteEscapesQuotesAndPercent;
begin
  AssertEqualsStr('"a""b%%c"', BatchQuote('a"b%c'));
end;

procedure SingleLineBodyStaysInline;
var F: TGeneratedFileArray;
begin
  F := Convert(Lines(['POST http://x', '', '{"a":1}']), False, False);
  AssertEqualsInt(1, Length(F));
  AssertTrue(Pos('--data-raw "{""a"":1}"', F[0].Content) > 0);
end;

procedure MultilineBodyIsSavedToFile;
var F: TGeneratedFileArray;
begin
  F := Convert(Lines(['POST http://x', '', '{', '"a":1', '}']), False, False);
  AssertEqualsInt(2, Length(F));
  AssertTrue(Pos('--data-binary "@%~dp0requests_body_1.txt"', F[0].Content) > 0);
  AssertEqualsStr('requests_body_1.txt', F[1].FileName);
  AssertEqualsStr('{'#10'"a":1'#10'}', F[1].Content);
end;

procedure BodyFilesAreNumberedByEndpoint;
var F: TGeneratedFileArray;
begin
  F := Convert(Lines(['GET http://a', '', 'POST http://b', '', 'x', 'y']), False, False);
  AssertEqualsInt(2, Length(F));
  AssertEqualsStr('requests_body_2.txt', F[1].FileName);
end;

procedure CommentsUseRem;
begin
  AssertTrue(Pos('REM one'#13#10, Convert(Lines(['# @name one', 'GET http://x']), False, True)[0].Content) > 0);
end;

procedure CurlBatIdSelectsBatchTarget;
var G: TCodeGenerator; P: THttpFileParser;
begin
  G := CreateCodeGenerator('curl-bat');
  P := NewParser('GET http://x');
  try AssertEqualsStr('requests.bat', G.Generate(P.HttpFile)[0].FileName); finally P.Free; G.Free; end;
end;

initialization
  RegisterTest('Generator.CurlBatch', 'uses .bat extension and @echo off preamble', UsesBatExtensionAndPreamble);
  RegisterTest('Generator.CurlBatch', 'default target is the .sh shell', DefaultTargetIsShell);
  RegisterTest('Generator.CurlBatch', 'multiline uses ^ and CRLF', MultilineUsesCaretAndCrLf);
  RegisterTest('Generator.CurlBatch', 'quote escapes quotes and percent', QuoteEscapesQuotesAndPercent);
  RegisterTest('Generator.CurlBatch', 'single-line body stays inline', SingleLineBodyStaysInline);
  RegisterTest('Generator.CurlBatch', 'multi-line body is saved to a file', MultilineBodyIsSavedToFile);
  RegisterTest('Generator.CurlBatch', 'body files are numbered by endpoint', BodyFilesAreNumberedByEndpoint);
  RegisterTest('Generator.CurlBatch', 'comments use REM', CommentsUseRem);
  RegisterTest('Generator.CurlBatch', 'curl-bat id selects batch target', CurlBatIdSelectsBatchTarget);
end.
