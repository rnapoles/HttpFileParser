unit Test_Response_Parsing;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, TestStubExecutor, HttpFileParser, HttpFileAST,
  HttpFileResponses, HttpFileResponseParser, HttpFileExecutor;

function ParseText(const AText: string): THttpResponse;
var P: THttpResponseParser;
begin
  P := THttpResponseParser.Create;
  try Result := P.Parse(AText); finally P.Free; end;
end;

procedure StatusLineAndHeaders;
var R: THttpResponse; V: string;
begin
  R := ParseText(Lines(['HTTP/1.1 200 OK', 'Content-Type: application/json', 'X-A:  1 ', '', '{}']));
  try
    AssertEqualsStr('HTTP/1.1', R.HttpVersion);
    AssertEqualsInt(200, R.StatusCode);
    AssertEqualsStr('OK', R.StatusText);
    AssertEqualsInt(2, R.HeaderCount);
    AssertTrue(R.FindHeader('content-type', V));
    AssertEqualsStr('application/json', V);
    AssertTrue(R.FindHeader('X-A', V));
    AssertEqualsStr('1', V);
  finally R.Free; end;
end;

procedure BodyIsKeptVerbatim;
var R: THttpResponse;
begin
  R := ParseText(Lines(['HTTP/1.1 200 OK', '', 'line1', '', '  line3']));
  try AssertEqualsStr('line1'#10#10'  line3', R.Body); finally R.Free; end;
end;

procedure CrLfLineEndings;
var R: THttpResponse; V: string;
begin
  R := ParseText('HTTP/1.1 201 Created'#13#10'X-A: 1'#13#10#13#10'body');
  try
    AssertEqualsInt(201, R.StatusCode);
    AssertEqualsStr('Created', R.StatusText);
    AssertTrue(R.FindHeader('X-A', V));
    AssertEqualsStr('body', R.Body);
  finally R.Free; end;
end;

procedure Http2WithoutReasonPhrase;
var R: THttpResponse;
begin
  R := ParseText('HTTP/2 204');
  try
    AssertEqualsInt(204, R.StatusCode);
    AssertEqualsStr('', R.StatusText);
    AssertEqualsStr('', R.Body);
  finally R.Free; end;
end;

procedure FoldedHeaderIsJoined;
var R: THttpResponse; V: string;
begin
  R := ParseText(Lines(['HTTP/1.1 200 OK', 'X-Long: first', '   second', '']));
  try
    AssertTrue(R.FindHeader('X-Long', V));
    AssertEqualsStr('first second', V);
  finally R.Free; end;
end;

procedure InterimResponsesAreSkipped;
var R: THttpResponse; V: string;
begin
  R := ParseText(Lines(['HTTP/1.1 100 Continue', '', 'HTTP/1.1 200 OK', 'A: b', '', 'ok']));
  try
    AssertEqualsInt(200, R.StatusCode);
    AssertEqualsInt(1, R.HeaderCount);
    AssertEqualsStr('ok', R.Body);
  finally R.Free; end;
end;

procedure InvalidStatusLineIsReportedWithRow;
var P: THttpResponseParser; Raised: Boolean; Row: Integer;
begin
  P := THttpResponseParser.Create;
  Raised := False;
  Row := 0;
  try
    try P.Parse(Lines(['', 'garbage']));
    except on E: EHttpResponseError do begin Raised := True; Row := E.Row; end; end;
  finally P.Free; end;
  AssertTrue(Raised);
  AssertEqualsInt(2, Row);
end;

procedure HeaderWithoutColonIsReported;
var P: THttpResponseParser; R: THttpResponse; Msg: string;
begin
  P := THttpResponseParser.Create;
  try
    AssertTrue(not P.TryParse(Lines(['HTTP/1.1 200 OK', 'nocolon', '']), R, Msg));
    AssertTrue(R = nil);
    AssertTrue(Pos('nocolon', Msg) > 0);
  finally P.Free; end;
end;

initialization
  RegisterTest('Response.Parsing', 'status line and headers', StatusLineAndHeaders);
  RegisterTest('Response.Parsing', 'body is kept verbatim', BodyIsKeptVerbatim);
  RegisterTest('Response.Parsing', 'CRLF line endings', CrLfLineEndings);
  RegisterTest('Response.Parsing', 'HTTP/2 without reason phrase', Http2WithoutReasonPhrase);
  RegisterTest('Response.Parsing', 'folded header is joined', FoldedHeaderIsJoined);
  RegisterTest('Response.Parsing', 'interim responses are skipped', InterimResponsesAreSkipped);
  RegisterTest('Response.Parsing', 'invalid status line is reported with row', InvalidStatusLineIsReportedWithRow);
  RegisterTest('Response.Parsing', 'header without colon is reported', HeaderWithoutColonIsReported);
end.
