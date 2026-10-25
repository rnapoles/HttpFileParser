(* CurlGenerator - converts every endpoint to a curl command script.

  By default the resolved values are used (variables replaced, functions
  evaluated at parse time). Everything shell specific lives in a TCurlDialect,
  so supporting another shell (PowerShell, fish, ...) means adding one dialect:

    Target = ctPosixShell   (default)  ->  <base>.sh   single-quoted, "\" continuation
    Target = ctWindowsBatch            ->  <base>.bat  double-quoted, "^" continuation,
                                                       CRLF line endings

  ExportVariables = True writes the file variables as shell variables at the top
  of the script and references them from the commands:

    .sh   baseUrl='http://h'      curl "${baseUrl}"'/a'
    .bat  set "baseUrl=http://h"  curl "%baseUrl%/a"

  A URL, header or body that contains a function call ($guid, $datetime, ...)
  keeps its evaluated, inlined text, because the value cannot be rebuilt from
  a shell variable (same for references like name.response.body...).
  Variables that depend on another response are exported empty and reported
  as warnings.

  Windows limitation: cmd cannot hold a line break inside an argument, so a
  multi-line body is saved next to the script as <base>_body_<n>.txt and sent
  with --data-binary "@%~dp0<file>" (the path is relative to the .bat file).
  The extra files are returned by Generate together with the script. *)
unit CurlGenerator;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, StrUtils, HttpFileAST, HttpFileReferences, CodeGenerator;

type
  TCurlTarget = (ctPosixShell, ctWindowsBatch);

  { A piece of a quoted argument: literal text or a reference to a shell variable. }
  TCurlTemplateSegment = record
    IsVariable: Boolean;
    Text: string; // literal text, or the shell variable name
  end;

  TCurlTemplateSegmentArray = array of TCurlTemplateSegment;

  { Strategy: how a curl script is spelled in one shell. }
  TCurlDialect = class
  public
    function FileExtension: string; virtual; abstract;
    function LineBreak: string; virtual; abstract;
    function Quote(const AValue: string): string; virtual; abstract;
    { one argument made of literal pieces and variable references }
    function QuoteSegments(const ASegments: TCurlTemplateSegmentArray): string; virtual; abstract;
    function AssignVariable(const AName, AValue: string): string; virtual; abstract;
    { argument for "--data-binary" pointing at a file stored next to the script }
    function BodyFileReference(const AFileName: string): string; virtual; abstract;
    function Comment(const AText: string): string; virtual; abstract;
    function ContinuationSuffix: string; virtual; abstract; // appended before a wrapped line
    function Preamble: string; virtual;                      // first lines of the file
    function SupportsMultilineValues: Boolean; virtual; abstract;
  end;

  TPosixCurlDialect = class(TCurlDialect)
  public
    function FileExtension: string; override;
    function LineBreak: string; override;
    function Quote(const AValue: string): string; override;
    function QuoteSegments(const ASegments: TCurlTemplateSegmentArray): string; override;
    function AssignVariable(const AName, AValue: string): string; override;
    function BodyFileReference(const AFileName: string): string; override;
    function Comment(const AText: string): string; override;
    function ContinuationSuffix: string; override;
    function SupportsMultilineValues: Boolean; override;
  end;

  TWindowsCurlDialect = class(TCurlDialect)
  public
    function FileExtension: string; override;
    function LineBreak: string; override;
    function Quote(const AValue: string): string; override;
    function QuoteSegments(const ASegments: TCurlTemplateSegmentArray): string; override;
    function AssignVariable(const AName, AValue: string): string; override;
    function BodyFileReference(const AFileName: string): string; override;
    function Comment(const AText: string): string; override;
    function ContinuationSuffix: string; override;
    function Preamble: string; override;
    function SupportsMultilineValues: Boolean; override;
  end;

  TCurlGenerator = class(TCodeGenerator)
  private
    FTarget: TCurlTarget;
    FMultiline: Boolean;
    FIncludeComments: Boolean;
    FExportVariables: Boolean;
    { state that only lives during DoGenerate }
    FDialect: TCurlDialect;
    FHttpFile: THttpFile;
    FBaseName: string;
    FExtraFiles: TGeneratedFileArray;
    function CreateDialect: TCurlDialect;
    function HasBody(AEndpoint: TEndpoint): Boolean;
    function SplitTemplate(const ARaw: string): TCurlTemplateSegmentArray;
    function ValueSegments(AEndpoint: TEndpoint; const AWhere, ARaw,
      AResolved: string): TCurlTemplateSegmentArray;
    function QuoteText(AEndpoint: TEndpoint; const AWhere, APrefix, ARaw,
      AResolved: string): string;
    function BuildVariableDefinitions: string;
    function BuildCommand(AEndpoint: TEndpoint; AIndex: Integer): string;
    procedure AddMethod(AArguments: TStrings; AEndpoint: TEndpoint);
    procedure AddHttpVersion(AArguments: TStrings; AEndpoint: TEndpoint);
    procedure AddHeaders(AArguments: TStrings; AEndpoint: TEndpoint);
    procedure AddBody(AArguments: TStrings; AEndpoint: TEndpoint; AIndex: Integer);
    procedure AddBodyFile(AArguments: TStrings; AEndpoint: TEndpoint; AIndex: Integer);
    function JoinArguments(AArguments: TStrings): string;
  protected
    function DoGenerate(AHttpFile: THttpFile; const ABaseName: string): TGeneratedFileArray; override;
  public
    constructor Create; override;
    class function Id: string; override;
    class function Description: string; override;
    { shell flavour of the output (default ctPosixShell -> .sh) }
    property Target: TCurlTarget read FTarget write FTarget;
    { one option per line, wrapped with the dialect's continuation (default True) }
    property Multiline: Boolean read FMultiline write FMultiline;
    { comment above each named command (default True) }
    property IncludeComments: Boolean read FIncludeComments write FIncludeComments;
    { define the file variables in the script and reference them (default False) }
    property ExportVariables: Boolean read FExportVariables write FExportVariables;
  end;

  { Same generator preconfigured for Windows batch files ('curl-bat'). }
  TCurlBatchGenerator = class(TCurlGenerator)
  public
    constructor Create; override;
    class function Id: string; override;
    class function Description: string; override;
  end;

function ShellQuote(const AValue: string): string;   // POSIX, single quotes
function BatchEscape(const AValue: string): string;  // Windows, text for inside "..."
function BatchQuote(const AValue: string): string;   // Windows cmd + curl.exe
function ShellVariableName(const AName: string): string;

implementation

function ShellQuote(const AValue: string): string;
begin
  // close quote, escaped quote, reopen quote:  '  ->  '\''
  Result := '''' + StringReplace(AValue, '''', '''\''''', [rfReplaceAll]) + '''';
end;

function BatchEscape(const AValue: string): string;
begin
  // %  -> %%  (batch expansion);  "  -> ""  (literal quote for curl.exe, keeps cmd's quote state balanced)
  Result := StringReplace(StringReplace(AValue, '%', '%%', [rfReplaceAll]),
    '"', '""', [rfReplaceAll]);
end;

function BatchQuote(const AValue: string): string;
begin
  Result := '"' + BatchEscape(AValue) + '"';
end;

function ShellVariableName(const AName: string): string;
var
  I: Integer;
begin
  Result := AName;
  for I := 1 to Length(Result) do
    if not (((Result[I] >= 'a') and (Result[I] <= 'z')) or
            ((Result[I] >= 'A') and (Result[I] <= 'Z')) or
            ((Result[I] >= '0') and (Result[I] <= '9')) or (Result[I] = '_')) then
      Result[I] := '_';
  if (Result = '') or ((Result[1] >= '0') and (Result[1] <= '9')) then
    Result := '_' + Result;
end;

procedure AppendSegment(var ASegments: TCurlTemplateSegmentArray; AIsVariable: Boolean;
  const AText: string);
var
  Last: Integer;
begin
  Last := High(ASegments);
  if (not AIsVariable) and (Last >= 0) and (not ASegments[Last].IsVariable) then
  begin
    ASegments[Last].Text := ASegments[Last].Text + AText; // merge neighbouring literals
    Exit;
  end;
  SetLength(ASegments, Length(ASegments) + 1);
  ASegments[High(ASegments)].IsVariable := AIsVariable;
  ASegments[High(ASegments)].Text := AText;
end;

{ TCurlDialect }

function TCurlDialect.Preamble: string;
begin
  Result := '';
end;

{ TPosixCurlDialect }

function TPosixCurlDialect.FileExtension: string;
begin
  Result := '.sh';
end;

function TPosixCurlDialect.LineBreak: string;
begin
  Result := #10;
end;

function TPosixCurlDialect.Quote(const AValue: string): string;
begin
  Result := ShellQuote(AValue);
end;

function TPosixCurlDialect.QuoteSegments(const ASegments: TCurlTemplateSegmentArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ASegments) do
    if ASegments[I].IsVariable then
      Result := Result + '"${' + ASegments[I].Text + '}"'
    else if ASegments[I].Text <> '' then
      Result := Result + ShellQuote(ASegments[I].Text);
  if Result = '' then
    Result := '''''';
end;

function TPosixCurlDialect.AssignVariable(const AName, AValue: string): string;
begin
  Result := AName + '=' + ShellQuote(AValue);
end;

function TPosixCurlDialect.BodyFileReference(const AFileName: string): string;
begin
  Result := ShellQuote('@' + AFileName);
end;

function TPosixCurlDialect.Comment(const AText: string): string;
begin
  Result := '# ' + AText;
end;

function TPosixCurlDialect.ContinuationSuffix: string;
begin
  Result := ' \';
end;

function TPosixCurlDialect.SupportsMultilineValues: Boolean;
begin
  Result := True;
end;

{ TWindowsCurlDialect }

function TWindowsCurlDialect.FileExtension: string;
begin
  Result := '.bat';
end;

function TWindowsCurlDialect.LineBreak: string;
begin
  Result := #13#10; // "^" continuation is unreliable with bare LF
end;

function TWindowsCurlDialect.Quote(const AValue: string): string;
begin
  Result := BatchQuote(AValue);
end;

function TWindowsCurlDialect.QuoteSegments(const ASegments: TCurlTemplateSegmentArray): string;
var
  I: Integer;
begin
  Result := '"';
  for I := 0 to High(ASegments) do
    if ASegments[I].IsVariable then
      Result := Result + '%' + ASegments[I].Text + '%'
    else
      Result := Result + BatchEscape(ASegments[I].Text);
  Result := Result + '"';
end;

function TWindowsCurlDialect.AssignVariable(const AName, AValue: string): string;
begin
  Result := 'set "' + AName + '=' + StringReplace(AValue, '%', '%%', [rfReplaceAll]) + '"';
end;

function TWindowsCurlDialect.BodyFileReference(const AFileName: string): string;
begin
  Result := '"@%~dp0' + BatchEscape(AFileName) + '"'; // %~dp0 = folder of the .bat file
end;

function TWindowsCurlDialect.Comment(const AText: string): string;
begin
  Result := 'REM ' + AText;
end;

function TWindowsCurlDialect.ContinuationSuffix: string;
begin
  Result := ' ^';
end;

function TWindowsCurlDialect.Preamble: string;
begin
  Result := '@echo off' + LineBreak + LineBreak;
end;

function TWindowsCurlDialect.SupportsMultilineValues: Boolean;
begin
  Result := False;
end;

{ TCurlGenerator }

constructor TCurlGenerator.Create;
begin
  inherited Create;
  FTarget := ctPosixShell;
  FMultiline := True;
  FIncludeComments := True;
  FExportVariables := False;
end;

class function TCurlGenerator.Id: string;
begin
  Result := 'curl';
end;

class function TCurlGenerator.Description: string;
begin
  Result := 'Shell script (.sh, or .bat via Target) with one curl command per request';
end;

function TCurlGenerator.CreateDialect: TCurlDialect;
begin
  case FTarget of
    ctWindowsBatch: Result := TWindowsCurlDialect.Create;
  else
    Result := TPosixCurlDialect.Create;
  end;
end;

function TCurlGenerator.HasBody(AEndpoint: TEndpoint): Boolean;
begin
  Result := (AEndpoint.BodyFilePath <> '') or (AEndpoint.RequestBody <> '');
end;

// templates: variable references in double braces become shell variable references

function TCurlGenerator.SplitTemplate(const ARaw: string): TCurlTemplateSegmentArray;
var
  I, CloseAt, RunStart: Integer;
  Inner: string;
begin
  Result := nil;
  I := 1;
  RunStart := 1;
  while I <= Length(ARaw) do
  begin
    if (ARaw[I] = '{') and (I < Length(ARaw)) and (ARaw[I + 1] = '{') then
    begin
      CloseAt := PosEx('}}', ARaw, I + 2);
      if CloseAt = 0 then
        Break;
      Inner := Trim(Copy(ARaw, I + 2, CloseAt - I - 2));
      if (Inner <> '') and (Inner[1] <> '$') and (FHttpFile.FindVariable(Inner) <> nil) then
      begin
        AppendSegment(Result, False, Copy(ARaw, RunStart, I - RunStart));
        AppendSegment(Result, True, ShellVariableName(Inner));
        RunStart := CloseAt + 2;
      end;
      I := CloseAt + 2;
    end
    else
      Inc(I);
  end;
  AppendSegment(Result, False, Copy(ARaw, RunStart, MaxInt));
end;

function TCurlGenerator.ValueSegments(AEndpoint: TEndpoint; const AWhere, ARaw,
  AResolved: string): TCurlTemplateSegmentArray;
var
  I: Integer;
begin
  if FExportVariables and (Pos('{{$', ARaw) = 0) and
     not HasRequestReference(FHttpFile, ARaw) then
    Result := SplitTemplate(ARaw)
  else
  begin
    Result := nil;
    AppendSegment(Result, False, AResolved);
  end;
  for I := 0 to High(Result) do
    if (not Result[I].IsVariable) and (Pos('{{', Result[I].Text) > 0) then
      WarnUnresolved(AEndpoint, AWhere, Result[I].Text);
end;

function TCurlGenerator.QuoteText(AEndpoint: TEndpoint; const AWhere, APrefix, ARaw,
  AResolved: string): string;
var
  Value, Combined: TCurlTemplateSegmentArray;
  I: Integer;
begin
  Value := ValueSegments(AEndpoint, AWhere, ARaw, AResolved);
  SetLength(Combined, 0);
  AppendSegment(Combined, False, APrefix);
  for I := 0 to High(Value) do
    AppendSegment(Combined, Value[I].IsVariable, Value[I].Text);
  Result := FDialect.QuoteSegments(Combined);
end;

function TCurlGenerator.BuildVariableDefinitions: string;
var
  I: Integer;
  V: TVariable;
  Value: string;
begin
  Result := '';
  for I := 0 to High(FHttpFile.Variables) do
  begin
    V := FHttpFile.Variables[I];
    if FHttpFile.FindVariable(V.Name) <> V then
      Continue; // redefined later: the last definition wins
    Value := V.Value;
    if (Pos('{{$', Value) > 0) or HasRequestReference(FHttpFile, Value) then
    begin
      AddWarning(Format('Variable "%s" (line %d) depends on a dynamic value, exported empty',
        [V.Name, V.Row]));
      Value := '';
    end;
    Result := Result + FDialect.AssignVariable(ShellVariableName(V.Name), Value) + FDialect.LineBreak;
  end;
  if Result <> '' then
    Result := Result + FDialect.LineBreak;
end;

{ arguments }

procedure TCurlGenerator.AddMethod(AArguments: TStrings; AEndpoint: TEndpoint);
var
  Verb: string;
begin
  Verb := UpperCase(AEndpoint.Verb);
  if Verb = 'HEAD' then
    AArguments.Add('--head')
  else if (Verb <> 'GET') or HasBody(AEndpoint) then
    AArguments.Add('-X ' + Verb);
end;

procedure TCurlGenerator.AddHttpVersion(AArguments: TStrings; AEndpoint: TEndpoint);
var
  Revision: string;
begin
  Revision := UpperCase(AEndpoint.HttpRevision);
  if Revision = 'HTTP/1.0' then
    AArguments.Add('--http1.0')
  else if (Revision = 'HTTP/2') or (Revision = 'HTTP/2.0') then
    AArguments.Add('--http2')
  else if (Revision = 'HTTP/3') or (Revision = 'HTTP/3.0') then
    AArguments.Add('--http3');
end;

procedure TCurlGenerator.AddHeaders(AArguments: TStrings; AEndpoint: TEndpoint);
var
  I: Integer;
  H: TRequestHeader;
begin
  for I := 0 to High(AEndpoint.RequestHeaders) do
  begin
    H := AEndpoint.RequestHeaders[I];
    AArguments.Add('-H ' + QuoteText(AEndpoint, 'header ' + H.Name, H.Name + ': ',
      H.RawValue, H.Value));
  end;
end;

procedure TCurlGenerator.AddBodyFile(AArguments: TStrings; AEndpoint: TEndpoint;
  AIndex: Integer);
var
  FileName: string;
begin
  WarnUnresolved(AEndpoint, 'body', AEndpoint.RequestBody);
  FileName := FBaseName + '_body_' + IntToStr(AIndex + 1) + '.txt';
  SetLength(FExtraFiles, Length(FExtraFiles) + 1);
  FExtraFiles[High(FExtraFiles)].FileName := FileName;
  FExtraFiles[High(FExtraFiles)].Content := AEndpoint.RequestBody;
  AArguments.Add('--data-binary ' + FDialect.BodyFileReference(FileName));
end;

procedure TCurlGenerator.AddBody(AArguments: TStrings; AEndpoint: TEndpoint;
  AIndex: Integer);
begin
  if AEndpoint.BodyFilePath <> '' then
    AArguments.Add('--data-binary ' + FDialect.Quote('@' + AEndpoint.BodyFilePath))
  else if AEndpoint.RequestBody <> '' then
  begin
    if (not FDialect.SupportsMultilineValues) and
       (Pos(#10, AEndpoint.RequestBody) + Pos(#13, AEndpoint.RequestBody) > 0) then
      AddBodyFile(AArguments, AEndpoint, AIndex)
    else
      AArguments.Add('--data-raw ' + QuoteText(AEndpoint, 'body', '',
        AEndpoint.RawRequestBody, AEndpoint.RequestBody));
  end;
end;

function TCurlGenerator.JoinArguments(AArguments: TStrings): string;
var
  I: Integer;
  Separator: string;
begin
  if FMultiline then
    Separator := FDialect.ContinuationSuffix + FDialect.LineBreak + '  '
  else
    Separator := ' ';
  Result := 'curl';
  for I := 0 to AArguments.Count - 1 do
    Result := Result + Separator + AArguments[I];
end;

function TCurlGenerator.BuildCommand(AEndpoint: TEndpoint; AIndex: Integer): string;
var
  Arguments: TStringList;
begin
  Arguments := TStringList.Create;
  try
    AddMethod(Arguments, AEndpoint);
    AddHttpVersion(Arguments, AEndpoint);
    Arguments.Add(QuoteText(AEndpoint, 'url', '', AEndpoint.RawUrl, AEndpoint.Url));
    AddHeaders(Arguments, AEndpoint);
    AddBody(Arguments, AEndpoint, AIndex);
    Result := JoinArguments(Arguments);
  finally
    Arguments.Free;
  end;
end;

function TCurlGenerator.DoGenerate(AHttpFile: THttpFile; const ABaseName: string): TGeneratedFileArray;
var
  I: Integer;
  Text: string;
begin
  Result := nil;
  FHttpFile := AHttpFile;
  FBaseName := ABaseName;
  SetLength(FExtraFiles, 0);
  FDialect := CreateDialect;
  try
    Text := FDialect.Preamble;
    if FExportVariables then
      Text := Text + BuildVariableDefinitions;
    for I := 0 to High(AHttpFile.Endpoints) do
    begin
      if I > 0 then
        Text := Text + FDialect.LineBreak;
      if FIncludeComments and (AHttpFile.Endpoints[I].Name <> '') then
        Text := Text + FDialect.Comment(AHttpFile.Endpoints[I].Name) + FDialect.LineBreak;
      Text := Text + BuildCommand(AHttpFile.Endpoints[I], I) + FDialect.LineBreak;
    end;
    SetLength(Result, 1 + Length(FExtraFiles));
    Result[0].FileName := ABaseName + FDialect.FileExtension;
    Result[0].Content := Text;
    for I := 0 to High(FExtraFiles) do
      Result[I + 1] := FExtraFiles[I];
  finally
    FreeAndNil(FDialect);
    FHttpFile := nil;
    SetLength(FExtraFiles, 0);
  end;
end;

{ TCurlBatchGenerator }

constructor TCurlBatchGenerator.Create;
begin
  inherited Create;
  Target := ctWindowsBatch;
end;

class function TCurlBatchGenerator.Id: string;
begin
  Result := 'curl-bat';
end;

class function TCurlBatchGenerator.Description: string;
begin
  Result := 'Windows batch file (.bat) with one curl command per request';
end;

initialization
  RegisterCodeGenerator(TCurlGenerator);
  RegisterCodeGenerator(TCurlBatchGenerator);

end.
