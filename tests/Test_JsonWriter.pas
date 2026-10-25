unit Test_JsonWriter;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, CodeGenerator, CurlGenerator, PostmanCollectionGenerator, JsonWriter;

procedure EmptyObject;
var W: TJsonWriter;
begin
  W := TJsonWriter.Create;
  try W.BeginObject; W.EndObject; AssertEqualsStr('{}', W.AsText); finally W.Free; end;
end;

procedure NestedStructureIsIndented;
var W: TJsonWriter;
begin
  W := TJsonWriter.Create;
  try
    W.BeginObject;
    W.WriteProperty('a', 'x');
    W.WriteName('b');
    W.BeginArray;
    W.WriteString('y');
    W.EndArray;
    W.EndObject;
    AssertEqualsStr('{'#10'  "a": "x",'#10'  "b": ['#10'    "y"'#10'  ]'#10'}', W.AsText);
  finally W.Free; end;
end;

procedure StringsAreEscaped;
begin
  AssertEqualsStr('a\"b\\c\n\u0001', JsonEscape('a"b\c'#10#1));
end;

initialization
  RegisterTest('JsonWriter', 'empty object', EmptyObject);
  RegisterTest('JsonWriter', 'nested structure is indented', NestedStructureIsIndented);
  RegisterTest('JsonWriter', 'strings are escaped', StringsAreEscaped);
end.
