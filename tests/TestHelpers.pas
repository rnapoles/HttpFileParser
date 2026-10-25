unit TestHelpers;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}

interface

uses
  SysUtils, HttpFileParser, HttpFileAST;

{ joins lines with LF }
function Lines(const AItems: array of string): string;
{ 2026-10-19 12:00:00 UTC (a Monday) }
function FixedNowUtc: TDateTime;
{ parser whose clock is frozen at FixedNowUtc with the given local offset }
function NewParser(const ASource: string; AOffsetMinutes: Integer = 0): THttpFileParser;
{ parses "POST http://x" + blank + AExpr and returns the first request body }
function EvalExpr(const AExpr: string; AOffsetMinutes: Integer = 0): string;

implementation

function Lines(const AItems: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := Low(AItems) to High(AItems) do
  begin
    if I > Low(AItems) then
      Result := Result + #10;
    Result := Result + AItems[I];
  end;
end;

function FixedNowUtc: TDateTime;
begin
  Result := EncodeDate(2026, 10, 19) + EncodeTime(12, 0, 0, 0);
end;

function NewParser(const ASource: string; AOffsetMinutes: Integer): THttpFileParser;
begin
  Result := THttpFileParser.Create(ASource);
  Result.Context.SetFixedNow(FixedNowUtc, AOffsetMinutes);
end;

function EvalExpr(const AExpr: string; AOffsetMinutes: Integer): string;
var
  P: THttpFileParser;
begin
  P := NewParser(Lines(['POST http://x', '', AExpr]), AOffsetMinutes);
  try
    Result := P.HttpFile.Endpoints[0].RequestBody;
  finally
    P.Free;
  end;
end;

end.
