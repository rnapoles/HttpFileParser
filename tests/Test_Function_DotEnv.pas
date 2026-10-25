unit Test_Function_DotEnv;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;

const
  Dir = 'dotenv_fixture';

function EvalWithEnv(const AExpr: string): string;
var
  Env: TStringList;
  P: THttpFileParser;
begin
  WriteLn(Dir);
  ForceDirectories(Dir);
  Env := TStringList.Create;
  try
    Env.Add('# comment');
    Env.Add('USERNAME=alice');
    Env.Add('export TOKEN="a b"');
    Env.SaveToFile(Dir + PathDelim + '.env');
  finally
    Env.Free;
  end;
  P := NewParser(Lines(['POST http://x', '', AExpr]));
  try
    P.BaseDirectory := Dir;
    Result := P.HttpFile.Endpoints[0].RequestBody;
  finally
    P.Free;
    DeleteFile(Dir + PathDelim + '.env');
    RemoveDir(Dir);
  end;
end;

procedure ReadsValueFromEnvFile;
begin
  AssertEqualsStr('alice', EvalWithEnv('{{$dotenv ''USERNAME''}}'));
end;

procedure StripsQuotesAndExportPrefix;
begin
  AssertEqualsStr('a b', EvalWithEnv('{{$dotenv TOKEN}}'));
end;

procedure MissingKeyIsEmpty;
begin
  AssertEqualsStr('', EvalWithEnv('{{$dotenv ''NOPE''}}'));
end;

procedure MissingEnvFileIsEmpty;
var P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', '{{$dotenv A}}']));
  try
    P.BaseDirectory := 'no_such_directory';
    AssertEqualsStr('', P.HttpFile.Endpoints[0].RequestBody);
    AssertEqualsInt(0, P.Errors.Count);
  finally P.Free; end;
end;

initialization
  RegisterTest('Function.DotEnv', 'reads value from .env', ReadsValueFromEnvFile);
  RegisterTest('Function.DotEnv', 'strips quotes and export prefix', StripsQuotesAndExportPrefix);
  RegisterTest('Function.DotEnv', 'missing key is empty', MissingKeyIsEmpty);
  RegisterTest('Function.DotEnv', 'missing .env file is empty', MissingEnvFileIsEmpty);
end.
