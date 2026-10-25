unit Test_Executor_RequestMessage;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, TestStubExecutor, HttpFileParser, HttpFileAST,
  HttpFileResponses, HttpFileResponseParser, HttpFileExecutor;

procedure CopiesMethodUrlHeadersAndBody;
var P: THttpFileParser; M: THttpRequestMessage;
begin
  P := NewParser(Lines(['@h = http://z', 'POST {{h}}/a HTTP/1.0', 'Accept: a/b', '', '{"a":1}']));
  try
    M := BuildRequestMessage(P.HttpFile.Endpoints[0], '');
    AssertEqualsStr('POST', M.Method);
    AssertEqualsStr('http://z/a', M.Url);
    AssertEqualsStr('HTTP/1.0', M.HttpVersion);
    AssertEqualsInt(1, Length(M.Headers));
    AssertEqualsStr('a/b', M.Headers[0].Value);
    AssertEqualsStr('{"a":1}', M.Body);
    AssertEqualsStr('', M.BodyFilePath);
  finally P.Free; end;
end;

procedure RelativeBodyFileIsMadeAbsolute;
var P: THttpFileParser; M: THttpRequestMessage;
begin
  P := NewParser(Lines(['POST http://x', '', '< ./a.xml']));
  try
    M := BuildRequestMessage(P.HttpFile.Endpoints[0], 'base');
    AssertTrue(not IsRelativePath(M.BodyFilePath), M.BodyFilePath);
    AssertEqualsStr('a.xml', ExtractFileName(M.BodyFilePath));
  finally P.Free; end;
end;

procedure MissingBodyFileIsReported;
var P: THttpFileParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor; Raised: Boolean;
begin
  P := NewParser(Lines(['POST http://x', '', '< ./does_not_exist.bin']));
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    Raised := False;
    try
      Stub.BodyBytes(BuildRequestMessage(P.HttpFile.Endpoints[0], ''));
    except
      on ERequestExecutor do Raised := True;
    end;
    AssertTrue(Raised);
  finally P.Free; end;
end;

procedure BodyBytesComeFromTextOrFile;
var P: THttpFileParser; Stub: TStubRequestExecutor; Exec: IRequestExecutor; F: TStringList;
begin
  F := TStringList.Create;
  try F.Add('from file'); F.SaveToFile('body_fixture.txt'); finally F.Free; end;
  P := NewParser(Lines(['POST http://x', '', 'inline', '', '###', 'POST http://y', '', '< ./body_fixture.txt']));
  try
    Stub := TStubRequestExecutor.Create(P);
    Exec := Stub;
    AssertEqualsStr('inline', Stub.BodyBytes(BuildRequestMessage(P.HttpFile.Endpoints[0], '')));
    AssertTrue(Pos('from file', Stub.BodyBytes(BuildRequestMessage(P.HttpFile.Endpoints[1], ''))) = 1);
  finally P.Free; DeleteFile('body_fixture.txt'); end;
end;

initialization
  RegisterTest('Executor.RequestMessage', 'copies method, url, headers and body', CopiesMethodUrlHeadersAndBody);
  RegisterTest('Executor.RequestMessage', 'relative body file is made absolute', RelativeBodyFileIsMadeAbsolute);
  RegisterTest('Executor.RequestMessage', 'missing body file is reported', MissingBodyFileIsReported);
  RegisterTest('Executor.RequestMessage', 'body bytes come from text or file', BodyBytesComeFromTextOrFile);
end.
