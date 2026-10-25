unit Test_Scripting_ErrorCases;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, HttpFileParser, HttpFileAST, HttpFileResponses,
  HttpFileReferences, HttpFileScripting;

function Errors(const AExpr: string; out AValue: string): Integer;
var P: THttpFileParser; Person: TPerson;
begin
  Person := NewPerson;
  P := NewParser('@v = {{' + AExpr + '}}');
  try
    P.Scripting.RegisterObject('person', Person);
    AValue := P.HttpFile.Variables[0].Value;
    Result := P.Errors.ErrorCount;
  finally P.Free; Person.Free; end;
end;

procedure UnknownPropertyIsReported;
var V: string;
begin
  AssertEqualsInt(1, Errors('person.Missing', V));
  AssertEqualsStr('{{person.Missing}}', V);
end;

procedure PublicNonPublishedPropertyIsNotReadable;
var V: string;
begin
  AssertEqualsInt(1, Errors('person.Secret', V));
end;

procedure ObjectValuedPropertyIsReported;
var V: string;
begin
  AssertEqualsInt(1, Errors('person.Address', V));
  AssertEqualsInt(1, Errors('person', V));
end;

procedure NilNestedObjectIsReported;
var V: string;
begin
  AssertEqualsInt(1, Errors('person.NoAddress.City', V));
end;

procedure PropertyOfScalarIsReported;
var V: string;
begin
  AssertEqualsInt(1, Errors('person.Name.Length', V));
end;

procedure UnknownObjectStaysRawWithoutError;
var V: string;
begin
  AssertEqualsInt(0, Errors('stranger.Name', V));
  AssertEqualsStr('{{stranger.Name}}', V);
end;

procedure UnregisteredObjectIsNoLongerAvailable;
var P: THttpFileParser; Person: TPerson;
begin
  Person := NewPerson;
  P := NewParser('@v = {{person.Name}}');
  try
    P.Scripting.RegisterObject('person', Person);
    P.Scripting.UnregisterObject('person');
    AssertEqualsStr('{{person.Name}}', P.HttpFile.Variables[0].Value);
  finally P.Free; Person.Free; end;
end;

initialization
  RegisterTest('Scripting.Errors', 'unknown property is reported', UnknownPropertyIsReported);
  RegisterTest('Scripting.Errors', 'public non-published property is not readable', PublicNonPublishedPropertyIsNotReadable);
  RegisterTest('Scripting.Errors', 'object valued property is reported', ObjectValuedPropertyIsReported);
  RegisterTest('Scripting.Errors', 'nil nested object is reported', NilNestedObjectIsReported);
  RegisterTest('Scripting.Errors', 'property of a scalar is reported', PropertyOfScalarIsReported);
  RegisterTest('Scripting.Errors', 'unknown object stays raw without error', UnknownObjectStaysRawWithoutError);
  RegisterTest('Scripting.Errors', 'unregistered object is no longer available', UnregisteredObjectIsNoLongerAvailable);
end.
