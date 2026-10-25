unit Test_Generator_CurlBatch;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, CodeGenerator, CurlGenerator;

const
  Header = '@echo off'#13#10#13#10;

function Convert(const ASource: string; AMultiline, AComments: Boolean;
  out AWarnings: Integer): TGeneratedFile;
var P: THttpFileParser; G: TCurlGenerator;
begin
  P := NewParser(ASource);
  G := TCurlGenerator.Create;
  try
    G.Target := ctWindowsBatch;
    G.Multiline := AMultiline;
    G.IncludeComments := AComments;
    Result := G.Generate(P.HttpFile)[0];
    AWarnings := G.Warnings.Count;
  finally G.Free; P.Free; end;
end;

procedure UsesBatExtensionAndPreamble;
var W: Integer; F: TGeneratedFile;
begin
  F := Convert('GET http://x/a', False, False, W);
  AssertEqualsStr('requests.bat', F.FileName);
  AssertEqualsStr(Header + 'curl "http://x/a"'#13#10, F.Content);
end;

procedure DefaultTargetIsShell;
var P: THttpFileParser; G: TCurlGenerator;
begin
  P := NewParser('GET http://x');
  G := TCurlGenerator.Create;
  try AssertEqualsStr('requests.sh', G.Generate(P.HttpFile)[0].FileName); finally G.Free; P.Free; end;
end;

procedure MultilineUsesCaretAndCrLf;
var W: Integer;
begin
  AssertEqualsStr(Header + 'curl ^'#13#10'  -X DELETE ^'#13#10'  "http://x"'#13#10,
    Convert('DELETE http://x', True, False, W).Content);
end;

procedure QuoteEscapesQuotesAndPercent;
begin
  AssertEqualsStr('"a""b%%c"', BatchQuote('a"b%c'));
end;

procedure MultilineBodyIsFlattenedWithWarning;
var W: Integer; F: TGeneratedFile;
begin
  F := Convert(Lines(['POST http://x', '', '{', '"a":1', '}']), False, False, W);
  AssertTrue(Pos('--data-raw "{ ""a"":1 }"', F.Content) > 0);
  AssertEqualsInt(1, W);
end;

procedure CommentsUseRem;
var W: Integer;
begin
  AssertTrue(Pos('REM one'#13#10, Convert(Lines(['# @name one', 'GET http://x']), False, True, W).Content) > 0);
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
  RegisterTest('Generator.CurlBatch', 'multi-line body is flattened with warning', MultilineBodyIsFlattenedWithWarning);
  RegisterTest('Generator.CurlBatch', 'comments use REM', CommentsUseRem);
  RegisterTest('Generator.CurlBatch', 'curl-bat id selects batch target', CurlBatIdSelectsBatchTarget);
end.
