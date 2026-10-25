{ CurlGenerator - converts every endpoint to a curl command script.

  Uses the resolved values (variables replaced, functions evaluated at parse
  time). Everything shell specific lives in a TCurlDialect, so supporting
  another shell (PowerShell, fish, ...) means adding one dialect class:

    Target = ctPosixShell   (default)  ->  <base>.sh   single-quoted, "\" continuation
    Target = ctWindowsBatch            ->  <base>.bat  double-quoted, "^" continuation,
                                                       CRLF line endings

  Windows limitation: cmd cannot hold a line break inside an argument, so line
  breaks of multi-line bodies are replaced by a space and a warning is added. }
unit CurlGenerator;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, HttpFileAST, CodeGenerator;

type
  TCurlTarget = (ctPosixShell, ctWindowsBatch);

  { Strategy: how a curl script is spelled in one shell. }
  TCurlDialect = class
  public
    function FileExtension: string; virtual; abstract;
    function LineBreak: string; virtual; abstract;
    function Quote(const AValue: string): string; virtual; abstract;
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
    function Comment(const AText: string): string; override;
    function ContinuationSuffix: string; override;
    function SupportsMultilineValues: Boolean; override;
  end;

  TWindowsCurlDialect = class(TCurlDialect)
  public
    function FileExtension: string; override;
    function LineBreak: string; override;
    function Quote(const AValue: string): string; override;
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
    FDialect: TCurlDialect; // only alive during DoGenerate
    function CreateDialect: TCurlDialect;
    function HasBody(AEndpoint: TEndpoint): Boolean;
    function BuildCommand(AEndpoint: TEndpoint): string;
    procedure AddMethod(AArguments: TStrings; AEndpoint: TEndpoint);
    procedure AddHttpVersion(AArguments: TStrings; AEndpoint: TEndpoint);
    procedure AddHeaders(AArguments: TStrings; AEndpoint: TEndpoint);
    procedure AddBody(AArguments: TStrings; AEndpoint: TEndpoint);
    function BodyForDialect(AEndpoint: TEndpoint): string;
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
  end;

  { Same generator preconfigured for Windows batch files ('curl-bat'). }
  TCurlBatchGenerator = class(TCurlGenerator)
  public
    constructor Create; override;
    class function Id: string; override;
    class function Description: string; override;
  end;

function ShellQuote(const AValue: string): string;  // POSIX
function BatchQuote(const AValue: string): string;  // Windows cmd + curl.exe

implementation

function ShellQuote(const AValue: string): string;
begin
  // close quote, escaped quote, reopen quote:  '  ->  '\''
  Result := '''' + StringReplace(AValue, '''', '''\''''', [rfReplaceAll]) + '''';
end;

function BatchQuote(const AValue: string): string;
begin
  // %  -> %%  (batch expansion);  "  -> ""  (literal quote for curl.exe, keeps cmd's quote state balanced)
  Result := '"' + StringReplace(StringReplace(AValue, '%', '%%', [rfReplaceAll]),
    '"', '""', [rfReplaceAll]) + '"';
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
    WarnUnresolved(AEndpoint, 'header ' + H.Name, H.Value);
    AArguments.Add('-H ' + FDialect.Quote(H.Name + ': ' + H.Value));
  end;
end;

function TCurlGenerator.BodyForDialect(AEndpoint: TEndpoint): string;
begin
  Result := AEndpoint.RequestBody;
  if FDialect.SupportsMultilineValues or (Pos(#10, Result) + Pos(#13, Result) = 0) then
    Exit;
  Result := StringReplace(Result, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  AddWarning(Format('%s (line %d): line breaks of the body were replaced by spaces ' +
    '(not supported inside a Windows batch argument)', [EndpointTitle(AEndpoint), AEndpoint.Row]));
end;

procedure TCurlGenerator.AddBody(AArguments: TStrings; AEndpoint: TEndpoint);
begin
  if AEndpoint.BodyFilePath <> '' then
    AArguments.Add('--data-binary ' + FDialect.Quote('@' + AEndpoint.BodyFilePath))
  else if AEndpoint.RequestBody <> '' then
  begin
    WarnUnresolved(AEndpoint, 'body', AEndpoint.RequestBody);
    AArguments.Add('--data-raw ' + FDialect.Quote(BodyForDialect(AEndpoint)));
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

function TCurlGenerator.BuildCommand(AEndpoint: TEndpoint): string;
var
  Arguments: TStringList;
begin
  Arguments := TStringList.Create;
  try
    AddMethod(Arguments, AEndpoint);
    AddHttpVersion(Arguments, AEndpoint);
    WarnUnresolved(AEndpoint, 'url', AEndpoint.Url);
    Arguments.Add(FDialect.Quote(AEndpoint.Url));
    AddHeaders(Arguments, AEndpoint);
    AddBody(Arguments, AEndpoint);
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
  FDialect := CreateDialect;
  try
    Text := FDialect.Preamble;
    for I := 0 to High(AHttpFile.Endpoints) do
    begin
      if I > 0 then
        Text := Text + FDialect.LineBreak;
      if FIncludeComments and (AHttpFile.Endpoints[I].Name <> '') then
        Text := Text + FDialect.Comment(AHttpFile.Endpoints[I].Name) + FDialect.LineBreak;
      Text := Text + BuildCommand(AHttpFile.Endpoints[I]) + FDialect.LineBreak;
    end;
    SetLength(Result, 1);
    Result[0].FileName := ABaseName + FDialect.FileExtension;
    Result[0].Content := Text;
  finally
    FreeAndNil(FDialect);
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
