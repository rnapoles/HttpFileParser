unit Test_Response_FileLoader;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, TestStubExecutor, HttpFileParser, HttpFileAST,
  HttpFileResponses, HttpFileResponseParser, HttpFileExecutor;

function Load(const AText: string; AStore: THttpResponseStore; out ALoader: THttpResponseFileLoader): Integer;
begin
  ALoader := THttpResponseFileLoader.Create;
  Result := ALoader.LoadFromText(AText, AStore);
end;

procedure LoadsSeveralNamedResponses;
var S: THttpResponseStore; L: THttpResponseFileLoader; V: string;
begin
  S := THttpResponseStore.Create;
  try
    AssertEqualsInt(2, Load(Lines(['### Login', '# @name login', 'HTTP/1.1 200 OK', 'X-AuthToken: abc', '',
      '{"id":7}', '', '###', '# @name getUser', 'HTTP/1.1 404 Not Found']), S, L));
    try
      AssertEqualsInt(0, L.Errors.Count);
      AssertEqualsInt(200, S.Find('login').StatusCode);
      AssertEqualsStr('{"id":7}', S.Find('login').Body);
      AssertTrue(S.Find('login').FindHeader('x-authtoken', V));
      AssertEqualsInt(404, S.Find('getUser').StatusCode);
    finally L.Free; end;
  finally S.Free; end;
end;

procedure TitleIsTheNameWithoutMetadata;
var S: THttpResponseStore; L: THttpResponseFileLoader;
begin
  S := THttpResponseStore.Create;
  try
    AssertEqualsInt(1, Load(Lines(['### login', 'HTTP/1.1 200 OK']), S, L));
    try AssertTrue(S.Find('login') <> nil); finally L.Free; end;
  finally S.Free; end;
end;

procedure ResponseWithoutNameIsReported;
var S: THttpResponseStore; L: THttpResponseFileLoader;
begin
  S := THttpResponseStore.Create;
  try
    AssertEqualsInt(0, Load(Lines(['###', 'HTTP/1.1 200 OK']), S, L));
    try
      AssertEqualsInt(1, L.Errors.ErrorCount);
      AssertEqualsInt(2, L.Errors[0].Row);
      AssertEqualsStr('ResponseName', L.Errors[0].Rule);
    finally L.Free; end;
  finally S.Free; end;
end;

procedure MalformedResponseIsReportedAtItsRow;
var S: THttpResponseStore; L: THttpResponseFileLoader;
begin
  S := THttpResponseStore.Create;
  try
    AssertEqualsInt(1, Load(Lines(['### a', 'HTTP/1.1 200 OK', '', '###', '# @name b', '', 'garbage']), S, L));
    try
      AssertEqualsInt(1, L.Errors.Count);
      AssertEqualsInt(7, L.Errors[0].Row);
      AssertEqualsStr('ResponseFormat', L.Errors[0].Rule);
    finally L.Free; end;
  finally S.Free; end;
end;

procedure LoadsFromFile;
var S: THttpResponseStore; L: THttpResponseFileLoader; F: TStringList;
begin
  F := TStringList.Create;
  try
    F.Add('# @name saved'); F.Add('HTTP/1.1 202 Accepted'); F.Add(''); F.Add('queued');
    F.SaveToFile('saved_responses_fixture.http');
  finally F.Free; end;
  S := THttpResponseStore.Create;
  L := THttpResponseFileLoader.Create;
  try
    AssertEqualsInt(1, L.LoadFromFile('saved_responses_fixture.http', S));
    AssertEqualsInt(202, S.Find('saved').StatusCode);
    AssertEqualsStr('queued', S.Find('saved').Body);
  finally L.Free; S.Free; DeleteFile('saved_responses_fixture.http'); end;
end;

procedure LoadedResponsesResolveReferences;
var P: THttpFileParser; L: THttpResponseFileLoader;
begin
  P := NewParser(Lines(['@t = {{login.response.headers.X-AuthToken}}', '# @name login', 'GET http://x']));
  L := THttpResponseFileLoader.Create;
  try
    L.LoadFromText(Lines(['# @name login', 'HTTP/1.1 200 OK', 'X-AuthToken: abc']), P.Responses);
    AssertEqualsStr('abc', P.HttpFile.Variables[0].Value);
  finally L.Free; P.Free; end;
end;

initialization
  RegisterTest('Response.FileLoader', 'loads several named responses', LoadsSeveralNamedResponses);
  RegisterTest('Response.FileLoader', 'title is the name without @name', TitleIsTheNameWithoutMetadata);
  RegisterTest('Response.FileLoader', 'response without a name is reported', ResponseWithoutNameIsReported);
  RegisterTest('Response.FileLoader', 'malformed response is reported at its row', MalformedResponseIsReportedAtItsRow);
  RegisterTest('Response.FileLoader', 'loads from a file', LoadsFromFile);
  RegisterTest('Response.FileLoader', 'loaded responses resolve references', LoadedResponsesResolveReferences);
end.
