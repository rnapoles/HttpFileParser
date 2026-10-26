{ CodeGenerator - base class, registry and file output for HTTP file converters.

  Extending: derive from TCodeGenerator, override Id, Description and DoGenerate,
  and call RegisterCodeGenerator(TMyGenerator) from the unit's initialization
  section. Callers find generators by Id and never depend on concrete classes
  (Open/Closed, Dependency Inversion). A generator may return several files
  (e.g. a Postman collection plus its environment).

  Generate is a template method: it validates the input, resets Warnings and
  delegates to DoGenerate. Generators report non-fatal conversion problems
  through AddWarning instead of failing. }
unit CodeGenerator;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, HttpFileAST;

type
  ECodeGenerator = class(Exception);

  TGeneratedFile = record
    FileName: string;
    Content: string;
  end;

  TGeneratedFileArray = array of TGeneratedFile;

  TCodeGenerator = class
  private
    FWarnings: TStringList;
  protected
    { the single extension point: build the output files for ABaseName }
    function DoGenerate(AHttpFile: THttpFile; const ABaseName: string): TGeneratedFileArray; virtual; abstract;
    procedure AddWarning(const AMessage: string);
    { "name" or "VERB url" when the endpoint has no name }
    function EndpointTitle(AEndpoint: TEndpoint): string;
    // warns when AText still contains a double-brace placeholder the file did not define
    procedure WarnUnresolved(AEndpoint: TEndpoint; const AWhere, AText: string);
  public
    constructor Create; virtual;
    destructor Destroy; override;
    class function Id: string; virtual; abstract;          // e.g. 'curl'
    class function Description: string; virtual; abstract; // shown in help texts
    function Generate(AHttpFile: THttpFile; const ABaseName: string = 'requests'): TGeneratedFileArray;
    property Warnings: TStringList read FWarnings;
  end;

  TCodeGeneratorClass = class of TCodeGenerator;
  TCodeGeneratorClassArray = array of TCodeGeneratorClass;

{ registry }
procedure RegisterCodeGenerator(AClass: TCodeGeneratorClass);
function FindCodeGeneratorClass(const AId: string): TCodeGeneratorClass; // nil when unknown
function RegisteredCodeGenerators: TCodeGeneratorClassArray;
function CreateCodeGenerator(const AId: string): TCodeGenerator;          // raises ECodeGenerator

{ output }
function SafeFileName(const AName: string): string;
procedure SaveGeneratedFiles(const AFiles: TGeneratedFileArray; const ADirectory: string);

implementation

var
  GGenerators: TCodeGeneratorClassArray;

{ TCodeGenerator }

constructor TCodeGenerator.Create;
begin
  inherited Create;
  FWarnings := TStringList.Create;
end;

destructor TCodeGenerator.Destroy;
begin
  FWarnings.Free;
  inherited Destroy;
end;

function TCodeGenerator.Generate(AHttpFile: THttpFile; const ABaseName: string): TGeneratedFileArray;
begin
  if AHttpFile = nil then
    raise ECodeGenerator.Create('No HTTP file to convert');
  FWarnings.Clear;
  Result := DoGenerate(AHttpFile, SafeFileName(ABaseName));
end;

procedure TCodeGenerator.AddWarning(const AMessage: string);
begin
  FWarnings.Add(AMessage);
end;

function TCodeGenerator.EndpointTitle(AEndpoint: TEndpoint): string;
begin
  if AEndpoint.Name <> '' then
    Result := AEndpoint.Name
  else
    Result := AEndpoint.Verb + ' ' + AEndpoint.Url;
end;

procedure TCodeGenerator.WarnUnresolved(AEndpoint: TEndpoint; const AWhere, AText: string);
begin
  if Pos('{{', AText) > 0 then
    AddWarning(Format('%s (line %d): unresolved placeholder in %s: %s',
      [EndpointTitle(AEndpoint), AEndpoint.Row, AWhere, AText]));
end;

{ registry }

procedure RegisterCodeGenerator(AClass: TCodeGeneratorClass);
var
  I: Integer;
begin
  for I := 0 to High(GGenerators) do
    if SameText(GGenerators[I].Id, AClass.Id) then
    begin
      GGenerators[I] := AClass; // re-registering replaces
      Exit;
    end;
  SetLength(GGenerators, Length(GGenerators) + 1);
  GGenerators[High(GGenerators)] := AClass;
end;

function FindCodeGeneratorClass(const AId: string): TCodeGeneratorClass;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(GGenerators) do
    if SameText(GGenerators[I].Id, AId) then
    begin
      Result := GGenerators[I];
      Exit;
    end;
end;

function RegisteredCodeGenerators: TCodeGeneratorClassArray;
begin
  Result := Copy(GGenerators, 0, Length(GGenerators));
end;

function CreateCodeGenerator(const AId: string): TCodeGenerator;
var
  GeneratorClass: TCodeGeneratorClass;
begin
  GeneratorClass := FindCodeGeneratorClass(AId);
  if GeneratorClass = nil then
    raise ECodeGenerator.CreateFmt('Unknown generator "%s"', [AId]);
  Result := GeneratorClass.Create;
end;

{ output }

function SafeFileName(const AName: string): string;
var
  I: Integer;
begin
  Result := Trim(AName);
  for I := 1 to Length(Result) do
    if Pos(Result[I], '\/:*?"<>|') > 0 then
      Result[I] := '_';
  if Result = '' then
    Result := 'requests';
end;

procedure SaveGeneratedFiles(const AFiles: TGeneratedFileArray; const ADirectory: string);
var
  I: Integer;
  Dir, Path: string;
  Stream: TFileStream;
  Data: RawByteString;
begin
  Dir := ADirectory;
  if Dir <> '' then
  begin
    ForceDirectories(Dir);
    Dir := IncludeTrailingPathDelimiter(Dir);
  end;
  for I := 0 to High(AFiles) do
  begin
    Path := Dir + AFiles[I].FileName;
    {$IFDEF FPC}
    Data := AFiles[I].Content;            // FPC strings already hold UTF-8 bytes
    {$ELSE}
    Data := UTF8Encode(AFiles[I].Content);
    {$ENDIF}
    Stream := TFileStream.Create(Path, fmCreate);
    try
      if Length(Data) > 0 then
        Stream.WriteBuffer(Data[1], Length(Data));
    finally
      Stream.Free;
    end;
  end;
end;

end.
