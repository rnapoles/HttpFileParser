(* PostmanCollectionGenerator - Postman Collection v2.1 plus environment file.

  Output files:  <base>.postman_collection.json
                 <base>.postman_environment.json

  Unlike curl, the collection keeps {{variable}} references (Postman resolves
  them from the environment); the environment is built from the file's
  variables. {{$guid}} / {{$timestamp}} / {{$randomInt}} map to Postman dynamic
  variables; other functions are kept as written and reported as warnings.
  Variables that depend on another response (name.response...) get an empty
  environment value. *)
unit PostmanCollectionGenerator;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, StrUtils, HttpFileAST, HttpFileReferences, CodeGenerator, JsonWriter;

type
  TPostmanCollectionGenerator = class(TCodeGenerator)
  private
    FCollectionName: string;
    FEnvironmentName: string;
    FHttpFile: THttpFile;
    function Translate(const AText, AContext: string): string;
    function TranslateExpression(const AInner, ARaw, AContext: string): string;
    function BodyLanguage(AEndpoint: TEndpoint): string;
    procedure WriteHeaders(AWriter: TJsonWriter; AEndpoint: TEndpoint);
    procedure WriteBody(AWriter: TJsonWriter; AEndpoint: TEndpoint);
    procedure WriteItem(AWriter: TJsonWriter; AEndpoint: TEndpoint);
    function BuildCollection(AHttpFile: THttpFile; const AName: string): string;
    function BuildEnvironment(AHttpFile: THttpFile; const AName: string): string;
  protected
    function DoGenerate(AHttpFile: THttpFile; const ABaseName: string): TGeneratedFileArray; override;
  public
    class function Id: string; override;
    class function Description: string; override;
    { default: the base name }
    property CollectionName: string read FCollectionName write FCollectionName;
    { default: "<collection name> Environment" }
    property EnvironmentName: string read FEnvironmentName write FEnvironmentName;
  end;

implementation

const
  CollectionSchema = 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json';

class function TPostmanCollectionGenerator.Id: string;
begin
  Result := 'postman';
end;

class function TPostmanCollectionGenerator.Description: string;
begin
  Result := 'Postman Collection v2.1 and environment files';
end;

// translation of double-brace expressions

function TPostmanCollectionGenerator.TranslateExpression(const AInner, ARaw,
  AContext: string): string;
var
  FnName, Msg: string;
  P: Integer;
  HasArgs: Boolean;
  Ref: TRequestReference;
begin
  Result := ARaw;
  if AInner = '' then
    Exit;
  if AInner[1] <> '$' then
  begin
    // plain variable: Postman resolves it from the environment
    if (MatchRequestReference(FHttpFile, AInner, Ref, Msg) = rmValid) and (Ref.Scope = rsResponse) then
      AddWarning(AContext + ': needs a Postman test script to read another response: ' + ARaw);
    Exit;
  end;
  FnName := LowerCase(Copy(AInner, 2, MaxInt));
  P := Pos(' ', FnName);
  HasArgs := P > 0;
  if HasArgs then
    FnName := Copy(FnName, 1, P - 1);

  if (FnName = 'guid') and not HasArgs then
    Result := '{{$guid}}'
  else if (FnName = 'timestamp') and not HasArgs then
    Result := '{{$timestamp}}'
  else if FnName = 'randomint' then
  begin
    Result := '{{$randomInt}}';
    AddWarning(AContext + ': Postman $randomInt ignores the range (0-1000): ' + ARaw);
  end
  else
    AddWarning(AContext + ': no Postman equivalent, kept as written: ' + ARaw);
end;

function TPostmanCollectionGenerator.Translate(const AText, AContext: string): string;
var
  I, CloseAt: Integer;
  Raw, Inner: string;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '{') and (I < Length(AText)) and (AText[I + 1] = '{') then
    begin
      CloseAt := PosEx('}}', AText, I + 2);
      if CloseAt = 0 then
      begin
        Result := Result + Copy(AText, I, MaxInt);
        Exit;
      end;
      Raw := Copy(AText, I, CloseAt + 2 - I);
      Inner := Trim(Copy(AText, I + 2, CloseAt - I - 2));
      Result := Result + TranslateExpression(Inner, Raw, AContext);
      I := CloseAt + 2;
    end
    else
    begin
      Result := Result + AText[I];
      Inc(I);
    end;
  end;
end;

{ collection }

function TPostmanCollectionGenerator.BodyLanguage(AEndpoint: TEndpoint): string;
var
  H: TRequestHeader;
  ContentType: string;
begin
  Result := 'text';
  H := AEndpoint.FindRequestHeader('Content-Type');
  if H = nil then
    Exit;
  ContentType := LowerCase(H.Value);
  if Pos('json', ContentType) > 0 then
    Result := 'json'
  else if Pos('xml', ContentType) > 0 then
    Result := 'xml'
  else if Pos('html', ContentType) > 0 then
    Result := 'html';
end;

procedure TPostmanCollectionGenerator.WriteHeaders(AWriter: TJsonWriter; AEndpoint: TEndpoint);
var
  I: Integer;
  H: TRequestHeader;
begin
  AWriter.WriteName('header');
  AWriter.BeginArray;
  for I := 0 to High(AEndpoint.RequestHeaders) do
  begin
    H := AEndpoint.RequestHeaders[I];
    AWriter.BeginObject;
    AWriter.WriteProperty('key', H.Name);
    AWriter.WriteProperty('value', Translate(H.RawValue, EndpointTitle(AEndpoint) + ' header ' + H.Name));
    AWriter.WriteProperty('type', 'text');
    AWriter.EndObject;
  end;
  AWriter.EndArray;
end;

procedure TPostmanCollectionGenerator.WriteBody(AWriter: TJsonWriter; AEndpoint: TEndpoint);
begin
  if AEndpoint.BodyFilePath <> '' then
  begin
    AWriter.WriteName('body');
    AWriter.BeginObject;
    AWriter.WriteProperty('mode', 'file');
    AWriter.WriteName('file');
    AWriter.BeginObject;
    AWriter.WriteProperty('src', AEndpoint.BodyFilePath);
    AWriter.EndObject;
    AWriter.EndObject;
  end
  else if AEndpoint.RawRequestBody <> '' then
  begin
    AWriter.WriteName('body');
    AWriter.BeginObject;
    AWriter.WriteProperty('mode', 'raw');
    AWriter.WriteProperty('raw', Translate(AEndpoint.RawRequestBody, EndpointTitle(AEndpoint) + ' body'));
    AWriter.WriteName('options');
    AWriter.BeginObject;
    AWriter.WriteName('raw');
    AWriter.BeginObject;
    AWriter.WriteProperty('language', BodyLanguage(AEndpoint));
    AWriter.EndObject;
    AWriter.EndObject;
    AWriter.EndObject;
  end;
end;

procedure TPostmanCollectionGenerator.WriteItem(AWriter: TJsonWriter; AEndpoint: TEndpoint);
begin
  AWriter.BeginObject;
  AWriter.WriteProperty('name', EndpointTitle(AEndpoint));
  AWriter.WriteName('request');
  AWriter.BeginObject;
  AWriter.WriteProperty('method', UpperCase(AEndpoint.Verb));
  WriteHeaders(AWriter, AEndpoint);
  WriteBody(AWriter, AEndpoint);
  AWriter.WriteName('url');
  AWriter.BeginObject;
  AWriter.WriteProperty('raw', Translate(AEndpoint.RawUrl, EndpointTitle(AEndpoint) + ' url'));
  AWriter.EndObject;
  AWriter.EndObject;
  AWriter.EndObject;
end;

function TPostmanCollectionGenerator.BuildCollection(AHttpFile: THttpFile; const AName: string): string;
var
  W: TJsonWriter;
  I: Integer;
begin
  W := TJsonWriter.Create;
  try
    W.BeginObject;
    W.WriteName('info');
    W.BeginObject;
    W.WriteProperty('name', AName);
    W.WriteProperty('schema', CollectionSchema);
    W.EndObject;
    W.WriteName('item');
    W.BeginArray;
    for I := 0 to High(AHttpFile.Endpoints) do
      WriteItem(W, AHttpFile.Endpoints[I]);
    W.EndArray;
    W.EndObject;
    Result := W.AsText + #10;
  finally
    W.Free;
  end;
end;

{ environment }

function TPostmanCollectionGenerator.BuildEnvironment(AHttpFile: THttpFile; const AName: string): string;
var
  W: TJsonWriter;
  I: Integer;
  V: TVariable;
  Value: string;
begin
  W := TJsonWriter.Create;
  try
    W.BeginObject;
    W.WriteProperty('name', AName);
    W.WriteName('values');
    W.BeginArray;
    for I := 0 to High(AHttpFile.Variables) do
    begin
      V := AHttpFile.Variables[I];
      if AHttpFile.FindVariable(V.Name) <> V then
        Continue; // redefined later: the last definition wins
      Value := V.Value;
      if (Pos('{{$', Value) > 0) or HasRequestReference(AHttpFile, Value) then
      begin
        AddWarning(Format('Variable "%s" (line %d) depends on a dynamic value, environment value left empty',
          [V.Name, V.Row]));
        Value := '';
      end;
      W.BeginObject;
      W.WriteProperty('key', V.Name);
      W.WriteProperty('value', Value);
      W.WriteProperty('type', 'default');
      W.WriteName('enabled');
      W.WriteBoolean(True);
      W.EndObject;
    end;
    W.EndArray;
    W.WriteProperty('_postman_variable_scope', 'environment');
    W.EndObject;
    Result := W.AsText + #10;
  finally
    W.Free;
  end;
end;

function TPostmanCollectionGenerator.DoGenerate(AHttpFile: THttpFile;
  const ABaseName: string): TGeneratedFileArray;
var
  CollectionTitle, EnvironmentTitle: string;
begin
  FHttpFile := AHttpFile;
  CollectionTitle := FCollectionName;
  if CollectionTitle = '' then
    CollectionTitle := ABaseName;
  EnvironmentTitle := FEnvironmentName;
  if EnvironmentTitle = '' then
    EnvironmentTitle := CollectionTitle + ' Environment';

  SetLength(Result, 2);
  Result[0].FileName := ABaseName + '.postman_collection.json';
  Result[0].Content := BuildCollection(AHttpFile, CollectionTitle);
  Result[1].FileName := ABaseName + '.postman_environment.json';
  Result[1].Content := BuildEnvironment(AHttpFile, EnvironmentTitle);
end;

initialization
  RegisterCodeGenerator(TPostmanCollectionGenerator);

end.
