unit TestLintHelpers;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
interface
uses SysUtils, HttpFileAST, HttpFileParser, HttpFileLinter, TestHelpers;

{ lints ASource with the parser's registries; the caller frees the list }
function LintSource(const ASource: string): THttpParseErrorList;
{ lints an already prepared parser (e.g. with registered objects) }
function LintParser(AParser: THttpFileParser): THttpParseErrorList;
function CountRule(AList: THttpParseErrorList; const ARule: string): Integer;
{ index of the first entry of ARule, -1 if none }
function IndexOfRule(AList: THttpParseErrorList; const ARule: string): Integer;

implementation

function LintParser(AParser: THttpFileParser): THttpParseErrorList;
var Linter: THttpFileLinter;
begin
  Result := THttpParseErrorList.Create;
  Linter := THttpFileLinter.Create(AParser.Functions, AParser.Scripting);
  try
    Linter.Lint(AParser.HttpFile, Result);
  finally Linter.Free; end;
end;

function LintSource(const ASource: string): THttpParseErrorList;
var P: THttpFileParser;
begin
  P := NewParser(ASource);
  try Result := LintParser(P); finally P.Free; end;
end;

function IndexOfRule(AList: THttpParseErrorList; const ARule: string): Integer;
var I: Integer;
begin
  for I := 0 to AList.Count - 1 do
    if AList[I].Rule = ARule then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function CountRule(AList: THttpParseErrorList; const ARule: string): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to AList.Count - 1 do
    if AList[I].Rule = ARule then
      Inc(Result);
end;

end.
