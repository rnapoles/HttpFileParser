unit Test_DateFormat_DayJs;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions, HttpFileDateFormat;

function Sample: TDateTime; // Monday 2026-10-19 15:04:05.006
begin
  Result := EncodeDate(2026, 10, 19) + EncodeTime(15, 4, 5, 6);
end;

procedure DateAndTimeTokens;
begin
  AssertEqualsStr('2026-10-19 15:04:05', FormatCustom(Sample, 0, 'YYYY-MM-DD HH:mm:ss'));
end;

procedure NamesAndUnpaddedTokens;
begin
  AssertEqualsStr('Monday October 19', FormatCustom(Sample, 0, 'dddd MMMM D'));
  AssertEqualsStr('Mon Oct', FormatCustom(Sample, 0, 'ddd MMM'));
end;

procedure TwelveHourClock;
begin
  AssertEqualsStr('03:04 PM', FormatCustom(Sample, 0, 'hh:mm A'));
  AssertEqualsStr('3:04 pm', FormatCustom(Sample, 0, 'h:mm a'));
end;

procedure BracketsEscapeText;
begin
  AssertEqualsStr('Today is Mon', FormatCustom(Sample, 0, '[Today is] ddd'));
end;

procedure MillisecondsAndOffsets;
begin
  AssertEqualsStr('006', FormatCustom(Sample, 0, 'SSS'));
  AssertEqualsStr('+05:30 +0530', FormatCustom(Sample, 330, 'Z ZZ'));
end;

initialization
  RegisterTest('DateFormat.DayJs', 'date and time tokens', DateAndTimeTokens);
  RegisterTest('DateFormat.DayJs', 'names and unpadded tokens', NamesAndUnpaddedTokens);
  RegisterTest('DateFormat.DayJs', 'twelve hour clock', TwelveHourClock);
  RegisterTest('DateFormat.DayJs', 'brackets escape text', BracketsEscapeText);
  RegisterTest('DateFormat.DayJs', 'milliseconds and offsets', MillisecondsAndOffsets);
end.
