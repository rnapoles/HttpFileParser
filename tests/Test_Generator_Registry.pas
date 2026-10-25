unit Test_Generator_Registry;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, CodeGenerator, CurlGenerator, PostmanCollectionGenerator, JsonWriter;

procedure BuiltInGeneratorsAreRegistered;
begin
  AssertTrue(FindCodeGeneratorClass('curl') = TCurlGenerator);
  AssertTrue(FindCodeGeneratorClass('postman') = TPostmanCollectionGenerator);
end;

procedure LookupIgnoresCase;
begin
  AssertTrue(FindCodeGeneratorClass('CURL') = TCurlGenerator);
end;

procedure UnknownIdRaises;
var Raised: Boolean;
begin
  Raised := False;
  try CreateCodeGenerator('nope').Free; except on ECodeGenerator do Raised := True; end;
  AssertTrue(Raised);
end;

procedure CreatedInstanceHasRequestedType;
var G: TCodeGenerator;
begin
  G := CreateCodeGenerator('curl');
  try AssertTrue(G is TCurlGenerator); finally G.Free; end;
end;

initialization
  RegisterTest('Generator.Registry', 'built-in generators are registered', BuiltInGeneratorsAreRegistered);
  RegisterTest('Generator.Registry', 'lookup ignores case', LookupIgnoresCase);
  RegisterTest('Generator.Registry', 'unknown id raises', UnknownIdRaises);
  RegisterTest('Generator.Registry', 'created instance has requested type', CreatedInstanceHasRequestedType);
end.
