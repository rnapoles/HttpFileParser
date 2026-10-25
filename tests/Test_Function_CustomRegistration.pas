unit Test_Function_CustomRegistration;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;

type
  TGreeter = class
    function Greet(const Args: THttpArgs; Context: THttpFunctionContext): string;
  end;

function TGreeter.Greet(const Args: THttpArgs; Context: THttpFunctionContext): string;
begin
  Result := 'hi ' + Args[0];
end;

function Upper(const Args: THttpArgs; Context: THttpFunctionContext): string;
begin
  Result := UpperCase(Args[0]);
end;

function Body(P: THttpFileParser): string;
begin
  Result := P.HttpFile.Endpoints[0].RequestBody;
end;

procedure PlainFunctionCanBeRegistered;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$upper ''abc def''}}']));
  try
    P.Functions.RegisterFunction('upper', Upper, 1, 1);
    AssertEqualsStr('ABC DEF', Body(P));
  finally P.Free; end;
end;

procedure MethodCanBeRegistered;
var P: THttpFileParser; G: TGreeter;
begin
  G := TGreeter.Create;
  P := NewParser(Lines(['POST http://x', '', '{{$hi bob}}']));
  try
    P.Functions.RegisterFunction('hi', G.Greet, 1, 1);
    AssertEqualsStr('hi bob', Body(P));
  finally P.Free; G.Free; end;
end;

procedure FunctionNamesIgnoreCase;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$UPPER x}}']));
  try
    P.Functions.RegisterFunction('Upper', Upper, 1, 1);
    AssertEqualsStr('X', Body(P));
  finally P.Free; end;
end;

procedure ArgumentCountIsValidated;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$upper}}']));
  try
    P.Functions.RegisterFunction('upper', Upper, 1, 1);
    AssertEqualsInt(1, P.Errors.Count);
    AssertEqualsStr('{{$upper}}', Body(P));
  finally P.Free; end;
end;

initialization
  RegisterTest('Function.Custom', 'plain function can be registered', PlainFunctionCanBeRegistered);
  RegisterTest('Function.Custom', 'method can be registered', MethodCanBeRegistered);
  RegisterTest('Function.Custom', 'names ignore case', FunctionNamesIgnoreCase);
  RegisterTest('Function.Custom', 'argument count is validated', ArgumentCountIsValidated);
end.
