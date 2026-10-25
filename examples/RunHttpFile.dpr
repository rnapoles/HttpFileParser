{ RunHttpFile - executes the requests of an .http file with libcurl.

  Usage:  RunHttpFile <file.http> [requestName] [--insecure]
  Without requestName every request runs in file order; each response is stored,
  the file is parsed again, and the next request resolves name.response...
  A request that refers to a response that does not exist yet is rejected.
  Needs libcurl at run time (libcurl.dll / libcurl.so / libcurl.dylib).
  Exit code: 0 = ok, 1 = parse errors or a request failed, 2 = usage / I/O error }
program RunHttpFile;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  HttpFileAST,
  HttpFileResponses,
  HttpFileParser,
  HttpFileExecutor,
  CurlRequestExecutor;

type
  TProgressPrinter = class
    procedure Executed(ASender: TObject; const ARequestName: string; AResponse: THttpResponse);
  end;

procedure TProgressPrinter.Executed(ASender: TObject; const ARequestName: string;
  AResponse: THttpResponse);
var
  Name: string;
  I: Integer;
begin
  Name := ARequestName;
  if Name = '' then
    Name := '(unnamed)';
  WriteLn(Format('%s -> %s %d %s', [Name, AResponse.HttpVersion, AResponse.StatusCode,
    AResponse.StatusText]));
  for I := 0 to AResponse.HeaderCount - 1 do
    WriteLn('  ', AResponse.Headers[I].Name, ': ', AResponse.Headers[I].Value);
  if AResponse.Body <> '' then
  begin
    WriteLn;
    WriteLn(AResponse.Body);
  end;
  WriteLn;
end;

var
  Parser: THttpFileParser;
  Executor: TCurlRequestExecutor;
  Runner: IRequestExecutor;
  Printer: TProgressPrinter;
  RequestName: string;
  I: Integer;
begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: RunHttpFile <file.http> [requestName] [--insecure]');
    Halt(2);
  end;
  if not FileExists(ParamStr(1)) then
  begin
    WriteLn('File not found: ', ParamStr(1));
    Halt(2);
  end;

  RequestName := '';
  Parser := THttpFileParser.CreateFromFile(ParamStr(1));
  Printer := TProgressPrinter.Create;
  try
    for I := 0 to Parser.Errors.Count - 1 do
      WriteLn('diagnostic: ', FormatParseError(Parser.Errors[I]));
    if Parser.Errors.HasErrors then
    begin
      ExitCode := 1;
      Exit;
    end;

    Executor := TCurlRequestExecutor.Create(Parser);
    Runner := Executor; // reference counted: released with Runner
    Executor.OnExecuted := Printer.Executed;
    for I := 2 to ParamCount do
      if SameText(ParamStr(I), '--insecure') then
        Executor.VerifyTls := False
      else
        RequestName := ParamStr(I);

    try
      if RequestName = '' then
        Runner.ExecuteAll
      else
        Runner.Execute(RequestName);
    except
      on E: ERequestExecutor do
      begin
        WriteLn('error: ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Runner := nil;
    Printer.Free;
    Parser.Free;
  end;
end.
