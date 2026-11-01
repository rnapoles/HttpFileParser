{ LintHttpFile - checks an .http file and prints one line per finding:
      file:row:column: severity: message [rule]
  (the format editors and CI log parsers understand).

  Usage:  LintHttpFile <file.http> [--strict]
  Reports the parser's syntax errors and the linter's warnings: duplicate
  request names, unused variables, unresolved placeholders, circular references.
  Exit code: 0 = no errors (warnings allowed), 1 = errors, or warnings with
  --strict, 2 = usage / I/O error }
program LintHttpFile;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  HttpFileAST,
  HttpFileParser,
  HttpFileLinter;

procedure Show(const AFileName: string; const AError: THttpParseError);
begin
  WriteLn(Format('%s:%d:%d: %s: %s [%s]', [AFileName, AError.Row, AError.Column,
    SeverityName(AError.Severity), AError.Message, AError.Rule]));
end;

var
  Parser: THttpFileParser;
  Linter: THttpFileLinter;
  Findings: THttpParseErrorList;
  Strict: Boolean;
  I: Integer;
begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: LintHttpFile <file.http> [--strict]');
    Halt(2);
  end;
  if not FileExists(ParamStr(1)) then
  begin
    WriteLn('File not found: ', ParamStr(1));
    Halt(2);
  end;
  Strict := (ParamCount >= 2) and SameText(ParamStr(2), '--strict');

  Parser := THttpFileParser.CreateFromFile(ParamStr(1));
  Linter := THttpFileLinter.Create(Parser.Functions, Parser.Scripting);
  Findings := THttpParseErrorList.Create;
  try
    // syntax errors come from the parser, the lint warnings from the linter
    for I := 0 to Parser.Errors.Count - 1 do
      if Parser.Errors[I].Severity = hsError then
        Show(ParamStr(1), Parser.Errors[I]);
    Linter.Lint(Parser.HttpFile, Findings);
    for I := 0 to Findings.Count - 1 do
      Show(ParamStr(1), Findings[I]);

    WriteLn(Format('%d error(s), %d warning(s)', [Parser.Errors.ErrorCount, Findings.WarningCount]));
    if Parser.Errors.HasErrors or (Strict and (Findings.Count > 0)) then
      ExitCode := 1;
  finally
    Findings.Free;
    Linter.Free;
    Parser.Free;
  end;
end.
