{ HttpFileDateFormat - RFC 1123, ISO 8601 and Day.js style formatting with
  locale-independent English names. All routines receive the *wall clock*
  time to display plus its UTC offset in minutes. }
unit HttpFileDateFormat;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils;

function FormatRfc1123(const AWall: TDateTime; AOffsetMinutes: Integer; AIsUtc: Boolean): string;
function FormatIso8601(const AWall: TDateTime; AOffsetMinutes: Integer; AIsUtc: Boolean): string;
{ Day.js tokens: YYYY YY MMMM MMM MM M DD D dddd ddd d HH H hh h mm m ss s SSS A a Z ZZ, [escaped] }
function FormatCustom(const AWall: TDateTime; AOffsetMinutes: Integer; const AFormat: string): string;

implementation

const
  DayNames: array[0..6] of string = (
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday');
  MonthNames: array[1..12] of string = (
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December');
  Tokens: array[0..23] of string = (
    'YYYY', 'YY', 'MMMM', 'MMM', 'MM', 'M', 'DD', 'D', 'dddd', 'ddd', 'd',
    'HH', 'H', 'hh', 'h', 'mm', 'm', 'ss', 's', 'SSS', 'ZZ', 'Z', 'A', 'a');

function Pad(AValue, AWidth: Integer): string;
begin
  Result := IntToStr(AValue);
  while Length(Result) < AWidth do
    Result := '0' + Result;
end;

function OffsetText(AOffsetMinutes: Integer; AWithColon: Boolean): string;
var
  Abs_: Integer;
begin
  if AOffsetMinutes < 0 then
    Result := '-'
  else
    Result := '+';
  Abs_ := Abs(AOffsetMinutes);
  Result := Result + Pad(Abs_ div 60, 2);
  if AWithColon then
    Result := Result + ':';
  Result := Result + Pad(Abs_ mod 60, 2);
end;

function TokenValue(const AToken: string; const AWall: TDateTime; AOffsetMinutes: Integer): string;
var
  Y, Mo, D, H, Mi, S, Ms: Word;
  H12: Integer;
begin
  DecodeDate(AWall, Y, Mo, D);
  DecodeTime(AWall, H, Mi, S, Ms);
  H12 := H mod 12;
  if H12 = 0 then
    H12 := 12;
  if AToken = 'YYYY' then Result := Pad(Y, 4)
  else if AToken = 'YY' then Result := Pad(Y mod 100, 2)
  else if AToken = 'MMMM' then Result := MonthNames[Mo]
  else if AToken = 'MMM' then Result := Copy(MonthNames[Mo], 1, 3)
  else if AToken = 'MM' then Result := Pad(Mo, 2)
  else if AToken = 'M' then Result := IntToStr(Mo)
  else if AToken = 'DD' then Result := Pad(D, 2)
  else if AToken = 'D' then Result := IntToStr(D)
  else if AToken = 'dddd' then Result := DayNames[DayOfWeek(AWall) - 1]
  else if AToken = 'ddd' then Result := Copy(DayNames[DayOfWeek(AWall) - 1], 1, 3)
  else if AToken = 'd' then Result := IntToStr(DayOfWeek(AWall) - 1)
  else if AToken = 'HH' then Result := Pad(H, 2)
  else if AToken = 'H' then Result := IntToStr(H)
  else if AToken = 'hh' then Result := Pad(H12, 2)
  else if AToken = 'h' then Result := IntToStr(H12)
  else if AToken = 'mm' then Result := Pad(Mi, 2)
  else if AToken = 'm' then Result := IntToStr(Mi)
  else if AToken = 'ss' then Result := Pad(S, 2)
  else if AToken = 's' then Result := IntToStr(S)
  else if AToken = 'SSS' then Result := Pad(Ms, 3)
  else if AToken = 'ZZ' then Result := OffsetText(AOffsetMinutes, False)
  else if AToken = 'Z' then Result := OffsetText(AOffsetMinutes, True)
  else if AToken = 'A' then
  begin
    if H < 12 then Result := 'AM' else Result := 'PM';
  end
  else if AToken = 'a' then
  begin
    if H < 12 then Result := 'am' else Result := 'pm';
  end
  else
    Result := AToken;
end;

function FormatCustom(const AWall: TDateTime; AOffsetMinutes: Integer; const AFormat: string): string;
var
  I, J, T: Integer;
  Matched: Boolean;
begin
  Result := '';
  I := 1;
  while I <= Length(AFormat) do
  begin
    if AFormat[I] = '[' then
    begin
      J := I + 1;
      while (J <= Length(AFormat)) and (AFormat[J] <> ']') do
        Inc(J);
      Result := Result + Copy(AFormat, I + 1, J - I - 1);
      I := J + 1;
    end
    else
    begin
      Matched := False;
      for T := Low(Tokens) to High(Tokens) do
        if Copy(AFormat, I, Length(Tokens[T])) = Tokens[T] then
        begin
          Result := Result + TokenValue(Tokens[T], AWall, AOffsetMinutes);
          Inc(I, Length(Tokens[T]));
          Matched := True;
          Break;
        end;
      if not Matched then
      begin
        Result := Result + AFormat[I];
        Inc(I);
      end;
    end;
  end;
end;

function FormatRfc1123(const AWall: TDateTime; AOffsetMinutes: Integer; AIsUtc: Boolean): string;
begin
  Result := FormatCustom(AWall, AOffsetMinutes, 'ddd, DD MMM YYYY HH:mm:ss');
  if AIsUtc then
    Result := Result + ' GMT'
  else
    Result := Result + ' ' + OffsetText(AOffsetMinutes, False);
end;

function FormatIso8601(const AWall: TDateTime; AOffsetMinutes: Integer; AIsUtc: Boolean): string;
begin
  Result := FormatCustom(AWall, AOffsetMinutes, 'YYYY-MM-DD[T]HH:mm:ss.SSS');
  if AIsUtc then
    Result := Result + 'Z'
  else
    Result := Result + OffsetText(AOffsetMinutes, True);
end;

end.
