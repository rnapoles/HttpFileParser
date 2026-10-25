{ ConvertHttpFile - converts an .http file with any registered generator.

  Usage:  ConvertHttpFile <file.http> <format> [outputDir]
  Formats: curl, postman  (any generator unit listed in "uses" registers itself) }
program ConvertHttpFile;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  HttpFileAST,
  HttpFileParser,
  CodeGenerator,
  CurlGenerator,              // registers 'curl'
  PostmanCollectionGenerator; // registers 'postman'

procedure PrintUsage;
var
  Classes: TCodeGeneratorClassArray;
  I: Integer;
begin
  WriteLn('Usage: ConvertHttpFile <file.http> <format> [outputDir]');
  WriteLn('Formats:');
  Classes := RegisteredCodeGenerators;
  for I := 0 to High(Classes) do
    WriteLn('  ', Classes[I].Id, ' - ', Classes[I].Description);
end;

var
  Parser: THttpFileParser;
  Generator: TCodeGenerator;
  Files: TGeneratedFileArray;
  OutDir, BaseName: string;
  I: Integer;
begin
  if ParamCount < 2 then
  begin
    PrintUsage;
    Halt(2);
  end;
  if not FileExists(ParamStr(1)) then
  begin
    WriteLn('File not found: ', ParamStr(1));
    Halt(2);
  end;
  if FindCodeGeneratorClass(ParamStr(2)) = nil then
  begin
    WriteLn('Unknown format: ', ParamStr(2));
    PrintUsage;
    Halt(2);
  end;

  if ParamCount >= 3 then
    OutDir := ParamStr(3)
  else
    OutDir := '.';
  BaseName := ChangeFileExt(ExtractFileName(ParamStr(1)), '');

  Parser := THttpFileParser.CreateFromFile(ParamStr(1));
  Generator := CreateCodeGenerator(ParamStr(2));

  if Generator is TCurlGenerator then
  begin
    TCurlGenerator(Generator).Target := ctWindowsBatch;
    TCurlGenerator(Generator).ExportVariables := True;
  end;
  
  try
    for I := 0 to Parser.Errors.Count - 1 do
      WriteLn('parse error: ', FormatParseError(Parser.Errors[I]));
    Files := Generator.Generate(Parser.HttpFile, BaseName);
    SaveGeneratedFiles(Files, OutDir);
    for I := 0 to High(Files) do
      WriteLn('written: ', IncludeTrailingPathDelimiter(OutDir) + Files[I].FileName);
    for I := 0 to Generator.Warnings.Count - 1 do
      WriteLn('warning: ', Generator.Warnings[I]);
  finally
    Generator.Free;
    Parser.Free;
  end;
end.
