(* HttpFileFunctions - function registry and built-in {{$functions}}.

  Custom functions are registered much like in PHP:

    function Upper(const Args: THttpArgs; Context: THttpFunctionContext): string;
    begin
      Result := UpperCase(Args[0]);
    end;
    ...
    Parser.Functions.RegisterFunction('upper', Upper, 1, 1);   // {{$upper 'abc'}}

  A handler may be a plain function or a method ("of object"). *)
unit HttpFileFunctions;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, DateUtils, HttpFileDateFormat;

type
  EHttpFunctionError = class(Exception);

  THttpArgs = array of string;

  { Environment shared by all function calls of one parse run. }
  THttpFunctionContext = class
  private
    FBaseDirectory: string;
    FHasFixedNow: Boolean;
    FFixedNow: TDateTime;
    FFixedOffset: Integer;
    FDotEnvLoaded: Boolean;
    FDotEnvKeys: TStringList;
    FDotEnvValues: TStringList;
    procedure LoadDotEnv;
  public
    constructor Create;
    destructor Destroy; override;
    { Freeze "now" (UTC) and the local UTC offset - used by tests. }
    procedure SetFixedNow(const AUtcNow: TDateTime; AOffsetMinutes: Integer = 0);
    function NowUtc: TDateTime;
    function LocalOffsetMinutes: Integer;
    function DotEnvValue(const AName: string; out AValue: string): Boolean;
    property BaseDirectory: string read FBaseDirectory write FBaseDirectory;
  end;

  THttpFunctionHandler = function(const Args: THttpArgs;
    Context: THttpFunctionContext): string;
  THttpFunctionMethod = function(const Args: THttpArgs;
    Context: THttpFunctionContext): string of object;

  THttpFunctionEntry = record
    Name: string; // lower case
    Handler: THttpFunctionHandler;
    Method: THttpFunctionMethod;
    MinArgs: Integer;
    MaxArgs: Integer; // -1 = unlimited
  end;

  THttpFunctionRegistry = class
  private
    FEntries: array of THttpFunctionEntry;
    function IndexOf(const AName: string): Integer;
    function AddEntry(const AName: string; AMinArgs, AMaxArgs: Integer): Integer;
  public
    constructor Create(AWithBuiltIns: Boolean = True);
    procedure RegisterBuiltIns;
    procedure RegisterFunction(const AName: string; AHandler: THttpFunctionHandler;
      AMinArgs: Integer = 0; AMaxArgs: Integer = -1); overload;
    procedure RegisterFunction(const AName: string; AMethod: THttpFunctionMethod;
      AMinArgs: Integer = 0; AMaxArgs: Integer = -1); overload;
    function IsRegistered(const AName: string): Boolean;
    function Execute(const AName: string; const AArgs: THttpArgs;
      AContext: THttpFunctionContext): string;
  end;

implementation

{ THttpFunctionContext }

constructor THttpFunctionContext.Create;
begin
  inherited Create;
  FDotEnvKeys := TStringList.Create;
  FDotEnvKeys.CaseSensitive := True;
  FDotEnvValues := TStringList.Create;
end;

destructor THttpFunctionContext.Destroy;
begin
  FDotEnvValues.Free;
  FDotEnvKeys.Free;
  inherited Destroy;
end;

procedure THttpFunctionContext.SetFixedNow(const AUtcNow: TDateTime; AOffsetMinutes: Integer);
begin
  FHasFixedNow := True;
  FFixedNow := AUtcNow;
  FFixedOffset := AOffsetMinutes;
end;

function THttpFunctionContext.NowUtc: TDateTime;
begin
  if FHasFixedNow then
    Result := FFixedNow
  else
  {$IFDEF FPC}
    Result := LocalTimeToUniversal(Now);
  {$ELSE}
    Result := TTimeZone.Local.ToUniversalTime(Now);
  {$ENDIF}
end;

function THttpFunctionContext.LocalOffsetMinutes: Integer;
begin
  if FHasFixedNow then
    Result := FFixedOffset
  else
    Result := Round((Now - NowUtc) * 1440);
end;

procedure THttpFunctionContext.LoadDotEnv;
var
  Lines: TStringList;
  Path, Line, Key, Val: string;
  I, P, Idx: Integer;
begin
  FDotEnvLoaded := True;
  if FBaseDirectory = '' then
    Path := '.env'
  else
    Path := IncludeTrailingPathDelimiter(FBaseDirectory) + '.env';
  if not FileExists(Path) then
    Exit;
  Lines := TStringList.Create;
  try
    {$IFDEF FPC}
    Lines.LoadFromFile(Path);
    {$ELSE}
    Lines.LoadFromFile(Path, TEncoding.UTF8);
    {$ENDIF}
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line[1] = '#') then
        Continue;
      if LowerCase(Copy(Line, 1, 7)) = 'export ' then
        Line := Trim(Copy(Line, 8, MaxInt));
      P := Pos('=', Line);
      if P < 2 then
        Continue;
      Key := Trim(Copy(Line, 1, P - 1));
      Val := Trim(Copy(Line, P + 1, MaxInt));
      if (Length(Val) >= 2) and ((Val[1] = '"') or (Val[1] = '''')) and
         (Val[Length(Val)] = Val[1]) then
        Val := Copy(Val, 2, Length(Val) - 2)
      else
      begin
        P := Pos(' #', Val);
        if P > 0 then
          Val := TrimRight(Copy(Val, 1, P - 1));
      end;
      Idx := FDotEnvKeys.IndexOf(Key);
      if Idx >= 0 then
        FDotEnvValues[Idx] := Val
      else
      begin
        FDotEnvKeys.Add(Key);
        FDotEnvValues.Add(Val);
      end;
    end;
  finally
    Lines.Free;
  end;
end;

function THttpFunctionContext.DotEnvValue(const AName: string; out AValue: string): Boolean;
var
  Idx: Integer;
begin
  if not FDotEnvLoaded then
    LoadDotEnv;
  Idx := FDotEnvKeys.IndexOf(AName);
  Result := Idx >= 0;
  if Result then
    AValue := FDotEnvValues[Idx]
  else
    AValue := '';
end;

{ built-in functions }

function UnixSeconds(const AUtc: TDateTime): Int64;
begin
  Result := Round((AUtc - 25569.0) * 86400.0); // 25569 = 1970-01-01
end;

function ApplyOffset(const ABase: TDateTime; const ANumber, AUnit: string): TDateTime;
var
  N: Int64;
begin
  if not TryStrToInt64(ANumber, N) then
    raise EHttpFunctionError.CreateFmt('Offset "%s" is not an integer', [ANumber]);
  if AUnit = 'ms' then Result := IncMilliSecond(ABase, N)
  else if AUnit = 's' then Result := IncSecond(ABase, N)
  else if AUnit = 'm' then Result := IncMinute(ABase, N)
  else if AUnit = 'h' then Result := IncHour(ABase, N)
  else if AUnit = 'd' then Result := IncDay(ABase, N)
  else if AUnit = 'w' then Result := IncWeek(ABase, N)
  else if AUnit = 'M' then Result := IncMonth(ABase, Integer(N))
  else if AUnit = 'y' then Result := IncYear(ABase, Integer(N))
  else
    raise EHttpFunctionError.CreateFmt(
      'Unknown offset unit "%s" (use ms, s, m, h, d, w, M or y)', [AUnit]);
end;

function FnGuid(const Args: THttpArgs; Context: THttpFunctionContext): string;
const
  Hex = '0123456789abcdef';
var
  B: array[0..15] of Byte;
  I: Integer;
begin
  for I := 0 to 15 do
    B[I] := Byte(Random(256));
  B[6] := (B[6] and $0F) or $40; // version 4
  B[8] := (B[8] and $3F) or $80; // RFC 4122 variant
  Result := '';
  for I := 0 to 15 do
  begin
    if (I = 4) or (I = 6) or (I = 8) or (I = 10) then
      Result := Result + '-';
    Result := Result + Hex[(B[I] shr 4) + 1] + Hex[(B[I] and $0F) + 1];
  end;
end;

function FnDotEnv(const Args: THttpArgs; Context: THttpFunctionContext): string;
begin
  Context.DotEnvValue(Args[0], Result);
end;

function FnRandomInt(const Args: THttpArgs; Context: THttpFunctionContext): string;
var
  MinV, MaxV, Range: Int64;
begin
  if not TryStrToInt64(Args[0], MinV) then
    raise EHttpFunctionError.Create('randomInt: min must be an integer');
  if not TryStrToInt64(Args[1], MaxV) then
    raise EHttpFunctionError.Create('randomInt: max must be an integer');
  Range := MaxV - MinV;
  if (Range <= 0) or (Range > High(LongInt)) then
    raise EHttpFunctionError.Create('randomInt: max must be greater than min');
  Result := IntToStr(MinV + Random(Integer(Range)));
end;

function FnTimestamp(const Args: THttpArgs; Context: THttpFunctionContext): string;
var
  Base: TDateTime;
begin
  Base := Context.NowUtc;
  if Length(Args) = 2 then
    Base := ApplyOffset(Base, Args[0], Args[1])
  else if Length(Args) <> 0 then
    raise EHttpFunctionError.Create('timestamp expects no arguments or "<number> <unit>"');
  Result := IntToStr(UnixSeconds(Base));
end;

function DateTimeCore(const Args: THttpArgs; Context: THttpFunctionContext;
  ALocal: Boolean): string;
var
  Base, Wall: TDateTime;
  Offset: Integer;
  Fmt: string;
begin
  Base := Context.NowUtc;
  if Length(Args) = 3 then
    Base := ApplyOffset(Base, Args[1], Args[2])
  else if Length(Args) <> 1 then
    raise EHttpFunctionError.Create('datetime expects "<format> [<number> <unit>]"');
  if ALocal then
    Offset := Context.LocalOffsetMinutes
  else
    Offset := 0;
  Wall := Base + Offset / 1440.0;
  Fmt := Args[0];
  if LowerCase(Fmt) = 'rfc1123' then
    Result := FormatRfc1123(Wall, Offset, not ALocal)
  else if LowerCase(Fmt) = 'iso8601' then
    Result := FormatIso8601(Wall, Offset, not ALocal)
  else
    Result := FormatCustom(Wall, Offset, Fmt);
end;

function FnDateTime(const Args: THttpArgs; Context: THttpFunctionContext): string;
begin
  Result := DateTimeCore(Args, Context, False);
end;

function FnLocalDateTime(const Args: THttpArgs; Context: THttpFunctionContext): string;
begin
  Result := DateTimeCore(Args, Context, True);
end;

{ THttpFunctionRegistry }

constructor THttpFunctionRegistry.Create(AWithBuiltIns: Boolean);
begin
  inherited Create;
  if AWithBuiltIns then
    RegisterBuiltIns;
end;

procedure THttpFunctionRegistry.RegisterBuiltIns;
begin
  RegisterFunction('guid', FnGuid, 0, 0);
  RegisterFunction('dotenv', FnDotEnv, 1, 1);
  RegisterFunction('randomInt', FnRandomInt, 2, 2);
  RegisterFunction('timestamp', FnTimestamp, 0, 2);
  RegisterFunction('datetime', FnDateTime, 1, 3);
  RegisterFunction('localDatetime', FnLocalDateTime, 1, 3);
end;

function THttpFunctionRegistry.IndexOf(const AName: string): Integer;
var
  I: Integer;
  Key: string;
begin
  Key := LowerCase(AName);
  for I := 0 to High(FEntries) do
    if FEntries[I].Name = Key then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function THttpFunctionRegistry.AddEntry(const AName: string; AMinArgs, AMaxArgs: Integer): Integer;
begin
  Result := IndexOf(AName);
  if Result < 0 then
  begin
    SetLength(FEntries, Length(FEntries) + 1);
    Result := High(FEntries);
  end;
  FEntries[Result].Name := LowerCase(AName);
  FEntries[Result].Handler := nil;
  FEntries[Result].Method := nil;
  FEntries[Result].MinArgs := AMinArgs;
  FEntries[Result].MaxArgs := AMaxArgs;
end;

procedure THttpFunctionRegistry.RegisterFunction(const AName: string;
  AHandler: THttpFunctionHandler; AMinArgs, AMaxArgs: Integer);
var
  Idx: Integer;
begin
  // AddEntry may reallocate FEntries: take the index first, then index the array
  Idx := AddEntry(AName, AMinArgs, AMaxArgs);
  FEntries[Idx].Handler := AHandler;
end;

procedure THttpFunctionRegistry.RegisterFunction(const AName: string;
  AMethod: THttpFunctionMethod; AMinArgs, AMaxArgs: Integer);
var
  Idx: Integer;
begin
  Idx := AddEntry(AName, AMinArgs, AMaxArgs);
  FEntries[Idx].Method := AMethod;
end;

function THttpFunctionRegistry.IsRegistered(const AName: string): Boolean;
begin
  Result := IndexOf(AName) >= 0;
end;

function THttpFunctionRegistry.Execute(const AName: string; const AArgs: THttpArgs;
  AContext: THttpFunctionContext): string;
var
  Idx: Integer;
begin
  Idx := IndexOf(AName);
  if Idx < 0 then
    raise EHttpFunctionError.CreateFmt('Unknown function "$%s"', [AName]);
  if Length(AArgs) < FEntries[Idx].MinArgs then
    raise EHttpFunctionError.CreateFmt('Function "$%s" expects at least %d argument(s)',
      [AName, FEntries[Idx].MinArgs]);
  if (FEntries[Idx].MaxArgs >= 0) and (Length(AArgs) > FEntries[Idx].MaxArgs) then
    raise EHttpFunctionError.CreateFmt('Function "$%s" expects at most %d argument(s)',
      [AName, FEntries[Idx].MaxArgs]);
  if Assigned(FEntries[Idx].Handler) then
    Result := FEntries[Idx].Handler(AArgs, AContext)
  else
    Result := FEntries[Idx].Method(AArgs, AContext);
end;

initialization
  Randomize;

end.
