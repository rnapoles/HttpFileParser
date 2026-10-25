unit Test_Parser_ValidSample;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST;

function SampleSource: string;
begin
  Result := Lines([
    '@baseUrl = http://localhost:8443',
    '@apiUrl = {{baseUrl}}/api/v1',
    '',
    '@authToken = {{loginRequest.response.body.$.payload.accessToken}}',
    '@refreshToken = {{loginRequest.response.body.$.payload.refreshToken}}',
    '@sessionId = {{loginRequest.response.body.$.payload.sessionId}}',
    '@csrfToken = {{loginCookie.response.body.$.payload.csrfToken}}',
    '',
    '@userId = {{createUser.response.body.$.payload.id}}',
    '@certificateId = {{createCertificate.response.body.$.payload.id}}',
    '@eventId = {{listAuditEvents.response.body.$.payload.items[0].id}}',
    '',
    '@publicOrigin = https://localhost:8443',
    '@contentType = application/json',
    '@mergePatch = application/merge-patch+json',
    '',
    '@login = root',
    '@password = +/Itu+II7VQLni8Z',
    '@otpCode = 437499',
    '',
    '### Login, tokens in the response body (scripts and services).',
    '# @name loginRequest',
    'POST {{apiUrl}}/auth/login',
    'Content-Type: {{contentType}}',
    '',
    '{',
    '  "login": "{{login}}",',
    '  "password": "{{password}}",',
    '  "otpCode": "{{otpCode}}",',
    '  "deviceName": "REST Client",',
    '  "tokenDelivery": "body"',
    '}',
    '',
    '### Login, tokens as HttpOnly cookies plus a CSRF token in the body (browser style, the default).',
    '# The Origin header is required for cookie sessions. REST Client keeps the cookies for later requests.',
    '# @name loginCookie',
    'POST {{apiUrl}}/auth/login',
    'Content-Type: {{contentType}}',
    'Origin: {{publicOrigin}}',
    '',
    '{',
    '  "login": "{{login}}",',
    '  "tokenDelivery": "cookie"',
    '}',
    '',
    '# @name = hello',
    'GET https://{{host}}/authors/{{name}} HTTP/1.1',
    '',
    '# @name PostXmlFile',
    'POST https://example.com/comments HTTP/1.1',
    'Content-Type: application/xml',
    'Authorization: token xxx',
    '',
    '< C:\Users\Default\Desktop\demo.xml # Only is valid here',
    '',
    '# @name SampleWithFunctions',
    'POST https://api.example.com/comments HTTP/1.1',
    'Content-Type: application/xml',
    'Date: {{$datetime rfc1123}}',
    '',
    '{',
    '    "user_name": "{{$dotenv ''USERNAME''}}",',
    '    "request_id": "{{$guid}}",',
    '    "updated_at": "{{$timestamp}}",',
    '    "created_at": "{{$timestamp -1 d}}",',
    '    "review_count": "{{$randomInt 5 200}}",',
    '    "custom_date": "{{$datetime ''YYYY-MM-DD''}}",',
    '    "local_custom_date": "{{$localDatetime ''YYYY-MM-DD''}}"',
    '}']);
end;

function Parse: THttpFileParser;
begin
  Result := NewParser(SampleSource);
end;

procedure ParsesWithoutErrors;
var P: THttpFileParser; I: Integer;
begin
  P := Parse;
  try
    for I := 0 to P.Errors.Count - 1 do
      if P.Errors[I].Severity = hsError then
        AssertTrue(False, FormatParseError(P.Errors[I]));
    AssertEqualsInt(15, Length(P.HttpFile.Variables));
    AssertEqualsInt(5, Length(P.HttpFile.Endpoints));
  finally P.Free; end;
end;

procedure ResolvesVariables;
var P: THttpFileParser;
begin
  P := Parse;
  try
    AssertEqualsStr('http://localhost:8443/api/v1', P.HttpFile.FindVariable('apiUrl').Value);
    AssertEqualsStr('{{loginRequest.response.body.$.payload.accessToken}}',
      P.HttpFile.FindVariable('authToken').Value);
  finally P.Free; end;
end;

procedure ParsesLoginRequests;
var P: THttpFileParser; E: TEndpoint;
begin
  P := Parse;
  try
    E := P.HttpFile.FindEndpoint('loginRequest');
    AssertEqualsStr('POST', E.Verb);
    AssertEqualsStr('http://localhost:8443/api/v1/auth/login', E.Url);
    AssertEqualsStr('application/json', E.FindRequestHeader('Content-Type').Value);
    AssertTrue(Pos('"login": "root"', E.RequestBody) > 0);
    AssertEqualsInt(2, Length(P.HttpFile.FindEndpoint('loginCookie').RequestHeaders));
  finally P.Free; end;
end;

procedure KeepsUnknownRequestVariables;
var P: THttpFileParser;
begin
  P := Parse;
  try
    AssertEqualsStr('https://{{host}}/authors/{{name}}', P.HttpFile.FindEndpoint('hello').Url);
  finally P.Free; end;
end;

procedure ParsesFileBody;
var P: THttpFileParser; E: TEndpoint;
begin
  P := Parse;
  try
    E := P.HttpFile.FindEndpoint('PostXmlFile');
    AssertEqualsStr('C:\Users\Default\Desktop\demo.xml', E.BodyFilePath);
    AssertEqualsInt(2, Length(E.RequestHeaders));
  finally P.Free; end;
end;

procedure ExpandsFunctions;
var P: THttpFileParser; E: TEndpoint;
begin
  P := Parse;
  try
    E := P.HttpFile.FindEndpoint('SampleWithFunctions');
    AssertEqualsStr('Mon, 19 Oct 2026 12:00:00 GMT', E.FindRequestHeader('Date').Value);
    AssertEqualsInt(0, Pos('{{', E.RequestBody));
    AssertTrue(Pos('"updated_at": "1792411200"', E.RequestBody) > 0);
    AssertTrue(Pos('"custom_date": "2026-10-19"', E.RequestBody) > 0);
    AssertTrue(Pos('{{$guid}}', E.RawRequestBody) > 0);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.ValidSample', 'parses without errors', ParsesWithoutErrors);
  RegisterTest('Parser.ValidSample', 'resolves variables', ResolvesVariables);
  RegisterTest('Parser.ValidSample', 'parses login requests', ParsesLoginRequests);
  RegisterTest('Parser.ValidSample', 'keeps unknown request variables', KeepsUnknownRequestVariables);
  RegisterTest('Parser.ValidSample', 'parses file body', ParsesFileBody);
  RegisterTest('Parser.ValidSample', 'expands functions', ExpandsFunctions);
end.
