unit Test_Scripting_Objects;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, HttpFileParser, HttpFileAST, HttpFileResponses,
  HttpFileReferences, HttpFileScripting;

function Eval(const AExpr: string): string;
var P: THttpFileParser; Person: TPerson;
begin
  Person := NewPerson;
  P := NewParser('@v = {{' + AExpr + '}}');
  try
    P.Scripting.RegisterObject('person', Person);
    Result := P.HttpFile.Variables[0].Value;
  finally P.Free; Person.Free; end;
end;

procedure ReadsStringProperty;
begin
  AssertEqualsStr('Ann', Eval('person.Name'));
end;

procedure ReadsIntegerAndFloatProperties;
begin
  AssertEqualsStr('41', Eval('person.Age'));
  AssertEqualsStr('2.5', Eval('person.Score'));
end;

procedure ReadsBooleanAndEnumProperties;
begin
  AssertEqualsStr('True', Eval('person.Active'));
  AssertEqualsStr('lvHigh', Eval('person.Level'));
end;

procedure WalksNestedObjects;
begin
  AssertEqualsStr('Lisbon', Eval('person.Address.City'));
end;

procedure NamesAreCaseInsensitive;
begin
  AssertEqualsStr('Ann', Eval('PERSON.name'));
end;

procedure UsableInRequests;
var P: THttpFileParser; Person: TPerson;
begin
  Person := NewPerson;
  P := NewParser(Lines(['GET http://x/{{person.Age}}', 'X-Name: {{person.Name}}', '', 'city={{person.Address.City}}']));
  try
    P.Scripting.RegisterObject('person', Person);
    AssertEqualsStr('http://x/41', P.HttpFile.Endpoints[0].Url);
    AssertEqualsStr('Ann', P.HttpFile.Endpoints[0].RequestHeaders[0].Value);
    AssertEqualsStr('city=Lisbon', P.HttpFile.Endpoints[0].RequestBody);
  finally P.Free; Person.Free; end;
end;

procedure FileVariableWinsOverObject;
var P: THttpFileParser; Person: TPerson;
begin
  Person := NewPerson;
  P := NewParser(Lines(['@person.Name = shadow', '@v = {{person.Name}}']));
  try
    P.Scripting.RegisterObject('person', Person);
    AssertEqualsStr('shadow', P.HttpFile.Variables[1].Value);
  finally P.Free; Person.Free; end;
end;

initialization
  RegisterTest('Scripting.Objects', 'reads string property', ReadsStringProperty);
  RegisterTest('Scripting.Objects', 'reads integer and float properties', ReadsIntegerAndFloatProperties);
  RegisterTest('Scripting.Objects', 'reads boolean and enum properties', ReadsBooleanAndEnumProperties);
  RegisterTest('Scripting.Objects', 'walks nested objects', WalksNestedObjects);
  RegisterTest('Scripting.Objects', 'names are case-insensitive', NamesAreCaseInsensitive);
  RegisterTest('Scripting.Objects', 'usable in url, headers and body', UsableInRequests);
  RegisterTest('Scripting.Objects', 'file variable wins over object', FileVariableWinsOverObject);
end.
