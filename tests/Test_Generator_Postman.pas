unit Test_Generator_Postman;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, CodeGenerator, CurlGenerator, PostmanCollectionGenerator, JsonWriter;

function Convert(const ASource: string; out AWarnings: Integer): TGeneratedFileArray;
var P: THttpFileParser; G: TPostmanCollectionGenerator;
begin
  P := NewParser(ASource);
  G := TPostmanCollectionGenerator.Create;
  try
    Result := G.Generate(P.HttpFile, 'api');
    AWarnings := G.Warnings.Count;
  finally G.Free; P.Free; end;
end;

procedure CreatesCollectionAndEnvironmentFiles;
var F: TGeneratedFileArray; W: Integer;
begin
  F := Convert('GET http://x', W);
  AssertEqualsInt(2, Length(F));
  AssertEqualsStr('api.postman_collection.json', F[0].FileName);
  AssertEqualsStr('api.postman_environment.json', F[1].FileName);
end;

procedure CollectionKeepsVariableReferences;
var F: TGeneratedFileArray; W: Integer;
begin
  F := Convert(Lines(['@h = http://z', '# @name one', 'POST {{h}}/p', 'Content-Type: application/json', '', '{"a":1}']), W);
  AssertTrue(Pos('"name": "one"', F[0].Content) > 0);
  AssertTrue(Pos('"method": "POST"', F[0].Content) > 0);
  AssertTrue(Pos('"raw": "{{h}}/p"', F[0].Content) > 0);
  AssertTrue(Pos('"language": "json"', F[0].Content) > 0);
  AssertTrue(Pos('"raw": "{\"a\":1}"', F[0].Content) > 0);
end;

procedure EnvironmentListsVariables;
var F: TGeneratedFileArray; W: Integer;
begin
  F := Convert('@baseUrl = http://h', W);
  AssertTrue(Pos('"key": "baseUrl"', F[1].Content) > 0);
  AssertTrue(Pos('"value": "http://h"', F[1].Content) > 0);
  AssertTrue(Pos('"_postman_variable_scope": "environment"', F[1].Content) > 0);
end;

procedure DynamicGuidMapsToPostman;
var F: TGeneratedFileArray; W: Integer;
begin
  F := Convert(Lines(['POST http://x', '', '{{$guid}}']), W);
  AssertTrue(Pos('"raw": "{{$guid}}"', F[0].Content) > 0);
  AssertEqualsInt(0, W);
end;

procedure JsonPathVariableIsEmptyAndWarned;
var F: TGeneratedFileArray; W: Integer;
begin
  F := Convert('@t = {{$jsonpath ''a.b''}}', W);
  AssertTrue(Pos('"value": ""', F[1].Content) > 0);
  AssertEqualsInt(1, W);
end;

procedure UnsupportedFunctionIsWarned;
var F: TGeneratedFileArray; W: Integer;
begin
  F := Convert(Lines(['POST http://x', '', '{{$datetime rfc1123}}']), W);
  AssertEqualsInt(1, W);
end;

initialization
  RegisterTest('Generator.Postman', 'creates collection and environment files', CreatesCollectionAndEnvironmentFiles);
  RegisterTest('Generator.Postman', 'collection keeps variable references', CollectionKeepsVariableReferences);
  RegisterTest('Generator.Postman', 'environment lists variables', EnvironmentListsVariables);
  RegisterTest('Generator.Postman', '$guid maps to Postman dynamic variable', DynamicGuidMapsToPostman);
  RegisterTest('Generator.Postman', 'jsonpath variable is empty and warned', JsonPathVariableIsEmptyAndWarned);
  RegisterTest('Generator.Postman', 'unsupported function is warned', UnsupportedFunctionIsWarned);
end.
