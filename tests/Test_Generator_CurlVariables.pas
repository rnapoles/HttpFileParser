unit Test_Generator_CurlVariables;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, CodeGenerator, CurlGenerator;

function Convert(const ASource: string; ATarget: TCurlTarget; AExport: Boolean;
  out AWarnings: Integer): string;
var P: THttpFileParser; G: TCurlGenerator;
begin
  P := NewParser(ASource);
  G := TCurlGenerator.Create;
  try
    G.Target := ATarget;
    G.ExportVariables := AExport;
    G.Multiline := False;
    G.IncludeComments := False;
    Result := G.Generate(P.HttpFile)[0].Content;
    AWarnings := G.Warnings.Count;
  finally G.Free; P.Free; end;
end;

function SimpleSource: string;
begin
  Result := Lines(['@baseUrl = http://h', 'GET {{baseUrl}}/a']);
end;

procedure DisabledByDefaultInlinesValues;
var W: Integer;
begin
  AssertEqualsStr('curl ''http://h/a'''#10, Convert(SimpleSource, ctPosixShell, False, W));
end;

procedure PosixDefinesAndReferencesVariables;
var W: Integer;
begin
  AssertEqualsStr('baseUrl=''http://h'''#10#10'curl "${baseUrl}"''/a'''#10,
    Convert(SimpleSource, ctPosixShell, True, W));
end;

procedure WindowsDefinesAndReferencesVariables;
var W: Integer;
begin
  AssertEqualsStr('@echo off'#13#10#13#10'set "baseUrl=http://h"'#13#10#13#10'curl "%baseUrl%/a"'#13#10,
    Convert(SimpleSource, ctWindowsBatch, True, W));
end;

procedure HeadersAndBodyUseReferences;
var W: Integer; S: string;
begin
  S := Convert(Lines(['@t = tok', 'POST http://x', 'Authorization: Bearer {{t}}', '', '{"k":"{{t}}"}']),
    ctPosixShell, True, W);
  AssertTrue(Pos('-H ''Authorization: Bearer ''"${t}"', S) > 0);
  AssertTrue(Pos('--data-raw ''{"k":"''"${t}"''"}''', S) > 0);
end;

procedure InvalidShellNamesAreSanitized;
var W: Integer;
begin
  AssertTrue(Pos('api_url=''x''', Convert('@api-url = x', ctPosixShell, True, W)) > 0);
end;

procedure DynamicVariableIsExportedEmptyWithWarning;
var W: Integer;
begin
  AssertTrue(Pos('t=''''', Convert(Lines(['@t = {{login.response.body.$.id}}', '# @name login', 'GET http://x']), ctPosixShell, True, W)) > 0);
  AssertEqualsInt(1, W);
end;

procedure FieldWithFunctionKeepsInlinedValue;
var W: Integer; S: string;
begin
  S := Convert(Lines(['@h = http://h', 'POST {{h}}/a', '', '{{$timestamp}}']), ctPosixShell, True, W);
  AssertTrue(Pos('"${h}"''/a''', S) > 0, 'url uses reference');
  AssertTrue(Pos('--data-raw ''1792411200''', S) > 0, 'body inlined');
end;

procedure UnknownPlaceholderIsWarned;
var W: Integer;
begin
  Convert('GET http://{{host}}/x', ctPosixShell, True, W);
  AssertEqualsInt(1, W);
end;

initialization
  RegisterTest('Generator.CurlVariables', 'disabled by default', DisabledByDefaultInlinesValues);
  RegisterTest('Generator.CurlVariables', 'POSIX defines and references variables', PosixDefinesAndReferencesVariables);
  RegisterTest('Generator.CurlVariables', 'Windows defines and references variables', WindowsDefinesAndReferencesVariables);
  RegisterTest('Generator.CurlVariables', 'headers and body use references', HeadersAndBodyUseReferences);
  RegisterTest('Generator.CurlVariables', 'invalid shell names are sanitized', InvalidShellNamesAreSanitized);
  RegisterTest('Generator.CurlVariables', 'dynamic variable is exported empty with warning', DynamicVariableIsExportedEmptyWithWarning);
  RegisterTest('Generator.CurlVariables', 'field with function keeps inlined value', FieldWithFunctionKeepsInlinedValue);
  RegisterTest('Generator.CurlVariables', 'unknown placeholder is warned', UnknownPlaceholderIsWarned);
end.
