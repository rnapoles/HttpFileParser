{ MiniTest - tiny dependency-free test harness that compiles with Delphi and FPC. }
unit MiniTest;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}

interface

uses
  SysUtils;

type
  TTestProc = procedure;
  ETestFailure = class(Exception);

procedure RegisterTest(const AFeature, AName: string; AProc: TTestProc);
procedure AssertTrue(ACondition: Boolean; const AMessage: string = '');
procedure AssertEqualsStr(const AExpected, AActual: string; const AMessage: string = '');
procedure AssertEqualsInt(AExpected, AActual: Int64; const AMessage: string = '');
function RunAllTests: Integer; // returns number of failures

implementation

type
  TTestEntry = record
    Feature: string;
    Name: string;
    Proc: TTestProc;
  end;

var
  GTests: array of TTestEntry;

procedure RegisterTest(const AFeature, AName: string; AProc: TTestProc);
begin
  SetLength(GTests, Length(GTests) + 1);
  GTests[High(GTests)].Feature := AFeature;
  GTests[High(GTests)].Name := AName;
  GTests[High(GTests)].Proc := AProc;
end;

procedure AssertTrue(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise ETestFailure.Create('Assertion failed. ' + AMessage);
end;

procedure AssertEqualsStr(const AExpected, AActual: string; const AMessage: string);
begin
  if AExpected <> AActual then
    raise ETestFailure.Create(Format('Expected "%s" but got "%s". %s',
      [AExpected, AActual, AMessage]));
end;

procedure AssertEqualsInt(AExpected, AActual: Int64; const AMessage: string);
begin
  if AExpected <> AActual then
    raise ETestFailure.Create(Format('Expected %d but got %d. %s',
      [AExpected, AActual, AMessage]));
end;

function RunAllTests: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(GTests) do
  try
    GTests[I].Proc;
    WriteLn('[PASS] ', GTests[I].Feature, ' :: ', GTests[I].Name);
  except
    on E: Exception do
    begin
      Inc(Result);
      WriteLn('[FAIL] ', GTests[I].Feature, ' :: ', GTests[I].Name, ' -> ', E.Message);
    end;
  end;
  WriteLn;
  WriteLn(Length(GTests), ' tests, ', Result, ' failed');
end;

end.
