unit Test_Reference_ResponseBody;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestFixtures, HttpFileParser, HttpFileAST, HttpFileResponses,
  HttpFileReferences, HttpFileScripting;

const
  Body = '{"payload":{"id":42,"name":"Bob","tags":["a","b"]}}';

function EvalVar(const ARef, ABody: string; out AErrors: Integer): string;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@v = {{' + ARef + '}}', '# @name login', 'GET http://x']));
  try
    P.Responses.Put('login').Body := ABody;
    Result := P.HttpFile.Variables[0].Value;
    AErrors := P.Errors.Count;
  finally P.Free; end;
end;

procedure NumberValue;
var E: Integer;
begin
  AssertEqualsStr('42', EvalVar('login.response.body.$.payload.id', Body, E));
  AssertEqualsInt(0, E);
end;

procedure StringValueHasNoQuotes;
var E: Integer;
begin
  AssertEqualsStr('Bob', EvalVar('login.response.body.$.payload.name', Body, E));
end;

procedure ArrayValueIsCompactJson;
var E: Integer;
begin
  AssertEqualsStr('["a","b"]', EvalVar('login.response.body.$.payload.tags', Body, E));
end;

procedure SeveralMatchesBecomeJsonArray;
var E: Integer;
begin
  AssertEqualsStr('["a","b"]', EvalVar('login.response.body.$.payload.tags[*]', Body, E));
end;

procedure StarReturnsWholeBody;
var E: Integer;
begin
  AssertEqualsStr(Body, EvalVar('login.response.body.*', Body, E));
end;

procedure NoMatchIsReportedAndKeptRaw;
var E: Integer;
begin
  AssertEqualsStr('{{login.response.body.$.nope}}', EvalVar('login.response.body.$.nope', Body, E));
  AssertEqualsInt(1, E);
end;

procedure InvalidJsonIsReported;
var E: Integer;
begin
  EvalVar('login.response.body.$.id', 'not json', E);
  AssertEqualsInt(1, E);
end;

procedure InvalidJsonPathIsReported;
var E: Integer;
begin
  EvalVar('login.response.body.$[', Body, E);
  AssertEqualsInt(1, E);
end;

initialization
  RegisterTest('Reference.ResponseBody', 'number value', NumberValue);
  RegisterTest('Reference.ResponseBody', 'string value has no quotes', StringValueHasNoQuotes);
  RegisterTest('Reference.ResponseBody', 'array value is compact JSON', ArrayValueIsCompactJson);
  RegisterTest('Reference.ResponseBody', 'several matches become a JSON array', SeveralMatchesBecomeJsonArray);
  RegisterTest('Reference.ResponseBody', '* returns the whole body', StarReturnsWholeBody);
  RegisterTest('Reference.ResponseBody', 'no match is reported and kept raw', NoMatchIsReportedAndKeptRaw);
  RegisterTest('Reference.ResponseBody', 'invalid JSON is reported', InvalidJsonIsReported);
  RegisterTest('Reference.ResponseBody', 'invalid JSONPath is reported', InvalidJsonPathIsReported);
end.
