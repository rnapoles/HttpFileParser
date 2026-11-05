unit Test_Incremental_Resolve;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestIncrementalHelpers, HttpFileParser, HttpFileAST,
  HttpFileResponses, HttpFileIncrementalParser, TestStubExecutor, HttpFileExecutor;

procedure GlobalPassSeesAnEditInAnotherSegment;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(Lines(['@base = http://a', '### r', 'GET {{base}}/x']));
  try
    AssertEqualsStr('http://a/x', P.HttpFile.Endpoints[0].Url);
    P.ApplyEdit(Pos('http://a', P.Text) + 7, 1, 'b');
    AssertEqualsStr('http://b/x', P.HttpFile.Endpoints[0].Url);
    AssertEqualsInt(1, P.LastReparsedCount);
    AssertEqualsInt(1, P.LastReusedCount);
  finally P.Free; end;
end;

procedure ParsingTwiceReusesEverything;
var P: THttpFileIncrementalParser; First: string;
begin
  P := NewIncremental(Lines(['@a = 1', '### r', 'GET http://x/{{a}}', '### s', 'GET http://y/{{zzz}}']));
  try
    First := Describe(P);
    P.Parse;
    P.Parse;
    AssertEqualsStr(First, Describe(P));
    AssertEqualsInt(3, P.SegmentCount);
  finally P.Free; end;
end;

procedure StoredResponsesAreNotBoundTwice;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(Lines(['# @name a', 'GET http://x']));
  try
    P.Responses.Put('a').AddHeader('X-A', '1');
    P.Parse;
    P.Parse;
    AssertEqualsInt(1, Length(P.HttpFile.Endpoints[0].ResponseHeaders));
    P.Responses.Clear;
    P.Parse;
    AssertEqualsInt(0, Length(P.HttpFile.Endpoints[0].ResponseHeaders));
  finally P.Free; end;
end;

procedure SyntaxErrorsKeepAbsoluteRowsAfterAShift;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(Lines(['@a = 1', '### s', 'junk text']));
  try
    AssertEqualsInt(3, P.Errors[0].Row);
    P.ApplyEdit(1, 0, '# c'#10);
    AssertEqualsInt(4, P.Errors[0].Row);
    AssertEqualsStr(FullParse(P.Text), Describe(P));
  finally P.Free; end;
end;

procedure RequestExecutorWorksOnAnIncrementalParser;
var P: THttpFileIncrementalParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor;
begin
  P := NewIncremental(Lines(['# @name login', 'POST http://x/login', '', '{"u":1}', '',
    '# @name getUser', 'GET http://x/users/{{login.response.body.$.id}}']));
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    Stub.Reply('http://x/login', 200, '{"id":7}');
    Exec.ExecuteAll;
    AssertEqualsStr('http://x/users/7', Stub.Sent(1).Url);
    AssertEqualsStr('{"id":7}', P.HttpFile.FindEndpoint('login').ResponseBody);
  finally P.Free; end;
end;

initialization
  RegisterTest('Incremental.Resolve', 'global pass sees an edit in another segment', GlobalPassSeesAnEditInAnotherSegment);
  RegisterTest('Incremental.Resolve', 'parsing twice reuses everything', ParsingTwiceReusesEverything);
  RegisterTest('Incremental.Resolve', 'stored responses are not bound twice', StoredResponsesAreNotBoundTwice);
  RegisterTest('Incremental.Resolve', 'syntax errors keep absolute rows after a shift', SyntaxErrorsKeepAbsoluteRowsAfterAShift);
  RegisterTest('Incremental.Resolve', 'request executor works on an incremental parser', RequestExecutorWorksOnAnIncrementalParser);
end.
