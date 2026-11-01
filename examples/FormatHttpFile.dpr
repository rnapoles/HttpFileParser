{ FormatHttpFile - prints an .http file in canonical form.

  Usage:  FormatHttpFile <file.http> [--resolved] [--crlf] [--write]
  --resolved  print the resolved values (what would be sent), not the raw text
  --crlf      use CRLF line breaks
  --write     overwrite the file instead of printing to the console
  A file with syntax errors is not printed (nothing is lost by formatting it).
  Exit code: 0 = ok, 1 = syntax errors, 2 = usage / I/O error }
program FormatHttpFile;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  HttpFileAST,
  HttpFileParser,
  HttpFilePrinter;

var
  Parser: THttpFileParser;
  Printer: THttpFilePrinter;
  WriteBack: Boolean;
  I: Integer;
begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: FormatHttpFile <file.http> [--resolved] [--crlf] [--write]');
    Halt(2);
  end;
  if not FileExists(ParamStr(1)) then
  begin
    WriteLn('File not found: ', ParamStr(1));
    Halt(2);
  end;

  WriteBack := False;
  Parser := THttpFileParser.CreateFromFile(ParamStr(1));
  Printer := THttpFilePrinter.Create;
  try
    for I := 2 to ParamCount do
      if SameText(ParamStr(I), '--resolved') then
        Printer.Resolved := True
      else if SameText(ParamStr(I), '--crlf') then
        Printer.LineBreak := #13#10
      else if SameText(ParamStr(I), '--write') then
        WriteBack := True;

    if Parser.Errors.HasErrors then
    begin
      for I := 0 to Parser.Errors.Count - 1 do
        if Parser.Errors[I].Severity = hsError then
          WriteLn(ErrOutput, FormatParseError(Parser.Errors[I]));
      ExitCode := 1;
      Exit;
    end;
    if WriteBack then
      Printer.SaveToFile(Parser.HttpFile, ParamStr(1))
    else
      Write(Printer.Print(Parser.HttpFile));
  finally
    Printer.Free;
    Parser.Free;
  end;
end.
