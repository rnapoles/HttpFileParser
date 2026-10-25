unit Test_Function_Arguments;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;

function Echo(const Args: THttpArgs; Context: THttpFunctionContext): string;
var I: Integer;
begin
  Result := '';
  for I := 0 to High(Args) do
  begin
    if I > 0 then Result := Result + '|';
    Result := Result + Args[I];
  end;
end;

function EvalEcho(const AExpr: string): string;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', AExpr]));
  try
    P.Functions.RegisterFunction('echo', Echo);
    Result := P.HttpFile.Endpoints[0].RequestBody;
  finally P.Free; end;
end;

procedure SplitsOnBlanks;
begin
  AssertEqualsStr('a|b|c', EvalEcho('{{$echo a  b   c}}'));
end;

procedure QuotesGroupBlanks;
begin
  AssertEqualsStr('a|b c|d e', EvalEcho('{{$echo a ''b c'' "d e"}}'));
end;

procedure UnterminatedQuoteIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$echo ''oops}}']));
  try
    P.Functions.RegisterFunction('echo', Echo);
    AssertEqualsInt(1, P.Errors.Count);
  finally P.Free; end;
end;

procedure UnterminatedExpressionIsReported;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', 'a {{b']));
  try
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsStr('a {{b', P.HttpFile.Endpoints[0].RequestBody);
  finally P.Free; end;
end;

initialization
  RegisterTest('Function.Arguments', 'splits on blanks', SplitsOnBlanks);
  RegisterTest('Function.Arguments', 'quotes group blanks', QuotesGroupBlanks);
  RegisterTest('Function.Arguments', 'unterminated quote is reported', UnterminatedQuoteIsReported);
  RegisterTest('Function.Arguments', 'unterminated expression is reported', UnterminatedExpressionIsReported);
end.
