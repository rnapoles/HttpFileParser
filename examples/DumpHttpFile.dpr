{ DumpHttpFile - loads the .http file given as the first argument and dumps
  what the parser understood: variables, endpoints and parse errors.

  Usage:  DumpHttpFile <file.http> [--demo]
  --demo  registers the object "app" and a stored response for the request
          "login" so the expressions of examples/features.http are resolved
  Exit code: 0 = no errors (warnings allowed), 1 = parse errors, 2 = usage / I/O error }
program DumpHttpFile;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  HttpFileAST,
  HttpFileResponses,
  HttpFileParser;

type
  { Any object with published properties can be registered; no wrapper code. }
  TDemoApp = class(TPersistent)
  private
    FName: string;
    FVersion: string;
    FEnvironment: string;
  public
    constructor Create;
  published
    property Name: string read FName;
    property Version: string read FVersion;
    property Environment: string read FEnvironment;
  end;

constructor TDemoApp.Create;
begin
  inherited Create;
  FName := 'demo-client';
  FVersion := '1.2.3';
  FEnvironment := 'staging';
end;

procedure RegisterDemo(AParser: THttpFileParser; AApp: TDemoApp);
var
  Response: THttpResponse;
begin
  AParser.Scripting.RegisterObject('app', AApp);
  // what an HTTP client would store after executing the "login" request
  Response := AParser.Responses.Put('login');
  Response.StatusCode := 200;
  Response.AddHeader('X-AuthToken', 'token-123');
  Response.Body :=
    '{"payload":{"accessToken":"at-456","user":{"id":7,"name":"Ann"},' +
    '"roles":["admin","dev"]}}';
end;

function Indent(const AText, APad: string): string;
begin
  Result := StringReplace(AText, #10, #10 + APad, [rfReplaceAll]);
end;

procedure DumpVariables(AFile: THttpFile);
var
  I: Integer;
  V: TVariable;
begin
  WriteLn('VARIABLES (', Length(AFile.Variables), ')');
  for I := 0 to High(AFile.Variables) do
  begin
    V := AFile.Variables[I];
    WriteLn(Format('  [%d:%d] %s', [V.Row, V.Column, V.Name]));
    WriteLn('      raw   = ', V.RawValue);
    WriteLn('      value = ', V.Value);
  end;
  WriteLn;
end;

procedure DumpEndpoint(AIndex: Integer; E: TEndpoint);
var
  J: Integer;
  H: TRequestHeader;
begin
  WriteLn(Format('ENDPOINT #%d  [%d:%d]  name="%s"', [AIndex + 1, E.Row, E.Column, E.Name]));
  WriteLn('  verb     = ', E.Verb);
  WriteLn('  url      = ', E.Url);
  if E.Url <> E.RawUrl then
    WriteLn('  raw url  = ', E.RawUrl);
  WriteLn('  revision = ', E.HttpRevision);
  WriteLn('  headers  = ', Length(E.RequestHeaders));
  for J := 0 to High(E.RequestHeaders) do
  begin
    H := E.RequestHeaders[J];
    WriteLn(Format('    [%d:%d] %s: %s', [H.Row, H.Column, H.Name, H.Value]));
    if H.Value <> H.RawValue then
      WriteLn('        raw: ', H.RawValue);
  end;
  if E.BodyFilePath <> '' then
    WriteLn('  body     = <file> ', E.BodyFilePath)
  else if E.RawRequestBody <> '' then
  begin
    WriteLn(Format('  body (starts at row %d):', [E.BodyRow]));
    WriteLn('    ', Indent(E.RequestBody, '    '));
    if E.RequestBody <> E.RawRequestBody then
    begin
      WriteLn('  raw body:');
      WriteLn('    ', Indent(E.RawRequestBody, '    '));
    end;
  end
  else
    WriteLn('  body     = (none)');
  WriteLn;
end;

procedure DumpErrors(AErrors: THttpParseErrorList);
var
  I: Integer;
begin
  WriteLn(Format('DIAGNOSTICS (%d errors, %d warnings)', [AErrors.ErrorCount, AErrors.WarningCount]));
  for I := 0 to AErrors.Count - 1 do
    WriteLn('  ', FormatParseError(AErrors[I]));
end;

var
  Parser: THttpFileParser;
  Demo: TDemoApp;
  I: Integer;
begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: DumpHttpFile <file.http> [--demo]');
    Halt(2);
  end;
  if not FileExists(ParamStr(1)) then
  begin
    WriteLn('File not found: ', ParamStr(1));
    Halt(2);
  end;

  Demo := nil;
  Parser := THttpFileParser.CreateFromFile(ParamStr(1));
  try
    if (ParamCount >= 2) and SameText(ParamStr(2), '--demo') then
    begin
      Demo := TDemoApp.Create;
      RegisterDemo(Parser, Demo); // before the first access: parsing is lazy
    end;
    WriteLn('FILE ', ParamStr(1));
    WriteLn;
    DumpVariables(Parser.HttpFile);
    WriteLn('ENDPOINTS (', Length(Parser.HttpFile.Endpoints), ')');
    WriteLn;
    for I := 0 to High(Parser.HttpFile.Endpoints) do
      DumpEndpoint(I, Parser.HttpFile.Endpoints[I]);
    DumpErrors(Parser.Errors);
    if Parser.Errors.HasErrors then
      ExitCode := 1; // warnings do not fail the run
  finally
    Parser.Free;
    If Assigned(Demo) then FreeAndNil(Demo);
  end;
end.
