unit Test_Parser_ErrorPositions;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

procedure MissingUrlIsReportedAfterVerb;
var P: THttpFileParser;
begin
  P := NewParser('GET');
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsInt(1, P.Errors[0].Row);
    AssertEqualsInt(4, P.Errors[0].Column);
    AssertEqualsStr('RequestLine', P.Errors[0].Rule);
    AssertEqualsInt(0, Length(P.HttpFile.Endpoints));
  finally P.Free; end;
end;

procedure TextOutsideRequestIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@a = 1', 'this is junk']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsInt(2, P.Errors[0].Row);
    AssertEqualsInt(1, P.Errors[0].Column);
    AssertEqualsStr('HttpFile', P.Errors[0].Rule);
    AssertEqualsStr('this is junk', P.Errors[0].Token);
  finally P.Free; end;
end;

procedure TextInHeaderSectionIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['GET http://x', 'junk here']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsInt(2, P.Errors[0].Row);
    AssertEqualsStr('HeaderLine', P.Errors[0].Rule);
  finally P.Free; end;
end;

procedure ParsingContinuesAfterAnError;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['junk', 'more junk', '@a = 1', 'GET http://x']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsInt(1, Length(P.HttpFile.Variables));
    AssertEqualsInt(1, Length(P.HttpFile.Endpoints));
  finally P.Free; end;
end;

procedure ErrorsAreSortedByPosition;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['@a = {{$nope}}', 'junk', 'GET http://x']));
  try
    AssertEqualsInt(2, P.Errors.Count);
    AssertEqualsInt(1, P.Errors[0].Row);
    AssertEqualsInt(2, P.Errors[1].Row);
  finally P.Free; end;
end;

initialization
  RegisterTest('Parser.ErrorPositions', 'missing URL is reported after the verb', MissingUrlIsReportedAfterVerb);
  RegisterTest('Parser.ErrorPositions', 'text outside request is reported', TextOutsideRequestIsReported);
  RegisterTest('Parser.ErrorPositions', 'text in header section is reported', TextInHeaderSectionIsReported);
  RegisterTest('Parser.ErrorPositions', 'parsing continues after an error', ParsingContinuesAfterAnError);
  RegisterTest('Parser.ErrorPositions', 'errors are sorted by position', ErrorsAreSortedByPosition);
end.
