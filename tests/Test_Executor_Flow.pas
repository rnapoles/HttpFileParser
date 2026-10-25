unit Test_Executor_Flow;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, TestStubExecutor, HttpFileParser, HttpFileAST,
  HttpFileResponses, HttpFileResponseParser, HttpFileExecutor;

function FlowSource: string;
begin
  Result := Lines(['# @name login', 'POST http://x/login', '', '{"user":"a"}', '',
    '# @name getUser', 'GET http://x/users/{{login.response.body.$.id}}',
    'Authorization: Bearer {{login.response.headers.X-AuthToken}}']);
end;

procedure ExecuteAllChainsResponses;
var P: THttpFileParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor;
begin
  P := NewParser(FlowSource);
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    Stub.Reply('http://x/login', 200, '{"id":7}').AddHeader('X-AuthToken', 'tok');
    Exec.ExecuteAll;
    AssertEqualsInt(2, Stub.SentCount);
    AssertEqualsStr('POST', Stub.Sent(0).Method);
    AssertEqualsStr('{"user":"a"}', Stub.Sent(0).Body);
    AssertEqualsStr('http://x/users/7', Stub.Sent(1).Url);
    AssertEqualsStr('Bearer tok', Stub.Sent(1).Headers[0].Value);
    AssertEqualsInt(404, P.Responses.Find('getUser').StatusCode);
  finally P.Free; end;
end;

procedure ExecutedRequestsAreBoundToTheAst;
var P: THttpFileParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor;
begin
  P := NewParser(FlowSource);
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    Stub.Reply('http://x/login', 200, '{"id":7}').AddHeader('X-AuthToken', 'tok');
    Exec.Execute('login');
    AssertEqualsStr('{"id":7}', P.HttpFile.FindEndpoint('login').ResponseBody);
    AssertEqualsInt(1, Length(P.HttpFile.FindEndpoint('login').ResponseHeaders));
    AssertEqualsStr('http://x/users/7', P.HttpFile.FindEndpoint('getUser').Url);
  finally P.Free; end;
end;

procedure RequestWithMissingResponseIsRejected;
var P: THttpFileParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor; Raised: Boolean;
begin
  P := NewParser(FlowSource);
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    Raised := False;
    try Exec.Execute('getUser'); except on ERequestExecutor do Raised := True; end;
    AssertTrue(Raised);
    AssertEqualsInt(0, Stub.SentCount, 'nothing may be sent');
  finally P.Free; end;
end;

procedure UnknownRequestIsRejected;
var P: THttpFileParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor; Raised: Boolean;
begin
  P := NewParser(FlowSource);
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    Raised := False;
    try Exec.Execute('nope'); except on ERequestExecutor do Raised := True; end;
    AssertTrue(Raised);
  finally P.Free; end;
end;

procedure UnnamedRequestIsExecutedButNotStored;
var P: THttpFileParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor;
begin
  P := NewParser('GET http://x/a');
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    Stub.Reply('http://x/a', 200, 'hi');
    AssertEqualsStr('hi', Exec.ExecuteAt(0).Body);
    AssertTrue(P.Responses.Find('') = nil);
  finally P.Free; end;
end;

type
  TRecorder = class
    Names: string;
    procedure Executed(ASender: TObject; const ARequestName: string; AResponse: THttpResponse);
  end;

procedure TRecorder.Executed(ASender: TObject; const ARequestName: string; AResponse: THttpResponse);
begin
  Names := Names + ARequestName + ':' + IntToStr(AResponse.StatusCode) + ';';
end;

procedure EventIsRaisedAfterEachRequest;
var P: THttpFileParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor; Rec: TRecorder;
begin
  P := NewParser(FlowSource);
  Rec := TRecorder.Create;
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    Stub.OnExecuted := Rec.Executed;
    Stub.Reply('http://x/login', 200, '{"id":7}').AddHeader('X-AuthToken', 'tok');
    Exec.ExecuteAll;
    AssertEqualsStr('login:200;getUser:404;', Rec.Names);
  finally Rec.Free; P.Free; end;
end;

initialization
  RegisterTest('Executor.Flow', 'ExecuteAll chains responses', ExecuteAllChainsResponses);
  RegisterTest('Executor.Flow', 'executed requests are bound to the AST', ExecutedRequestsAreBoundToTheAst);
  RegisterTest('Executor.Flow', 'request with a missing response is rejected', RequestWithMissingResponseIsRejected);
  RegisterTest('Executor.Flow', 'unknown request is rejected', UnknownRequestIsRejected);
  RegisterTest('Executor.Flow', 'unnamed request is executed but not stored', UnnamedRequestIsExecutedButNotStored);
  RegisterTest('Executor.Flow', 'event is raised after each request', EventIsRaisedAfterEachRequest);
end.
