unit Test_Incremental_Property;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestIncrementalHelpers, HttpFileParser, HttpFileAST,
  HttpFileIncrementalParser;

{ The one rule of incremental parsing: after ANY edit the result equals a full parse of
  the same text. Random edits are drawn from lines that exercise separators, names,
  scripts, bodies, variables and references. The seed is fixed, so a failure repeats. }

const
  Fragments: array[0..19] of string = (
    '@a = 1', '@b = {{a}}/x', '### Title', '###', '# @name r1', '# @name r2', '# @name',
    '# note', 'GET http://x/{{a}}', 'POST http://y/{{r1.response.body.$.id}}',
    'Accept: text/plain', '', '{"k":{{b}}}', '< {%', '%}', 'client.log(1) %}', 'junk text',
    '< ./f.xml # c', 'GET http://z HTTP/1.0', '  ?q=1');

function RandomText(ALines: Integer): string;
var I: Integer;
begin
  Result := '';
  for I := 1 to ALines do
    Result := Result + Fragments[Random(Length(Fragments))] + #10;
end;

function RandomInsert: string;
var Fragment: string;
begin
  Fragment := Fragments[Random(Length(Fragments))];
  case Random(5) of
    0: Result := '';
    1: Result := Fragment + #10;
    2: Result := #10;
    3: Result := Copy(Fragment, 1, Random(Length(Fragment) + 1)); // half a line
  else
    Result := Fragment + #13#10;
  end;
end;

procedure RandomEditsMatchAFullParse;
var
  P: THttpFileIncrementalParser;
  Step, Position, Deleted: Integer;
begin
  RandSeed := 20260101;
  P := NewIncremental(RandomText(14));
  try
    AssertEqualsStr(FullParse(P.Text), Describe(P), 'initial text');
    for Step := 1 to 300 do
    begin
      Position := 1 + Random(Length(P.Text) + 1);
      Deleted := Random(14);
      if Position + Deleted > Length(P.Text) + 1 then
        Deleted := Length(P.Text) + 1 - Position;
      P.ApplyEdit(Position, Deleted, RandomInsert);
      AssertEqualsStr(FullParse(P.Text), Describe(P),
        Format('step %d (position %d, deleted %d) text:'#10'%s', [Step, Position, Deleted, P.Text]));
    end;
  finally P.Free; end;
end;

procedure RandomWholeTextReplacementsMatchAFullParse;
var
  P: THttpFileIncrementalParser;
  Step: Integer;
  Text: string;
begin
  RandSeed := 77;
  Text := RandomText(10);
  P := NewIncremental(Text);
  try
    for Step := 1 to 80 do
    begin
      // change a few lines of the previous text: SetText has to find the difference itself
      Text := Copy(Text, 1, Random(Length(Text)) + 1) + RandomInsert + Copy(Text, Random(Length(Text)) + 1, MaxInt);
      P.SetText(Text);
      AssertEqualsStr(FullParse(P.Text), Describe(P), Format('step %d text:'#10'%s', [Step, P.Text]));
    end;
  finally P.Free; end;
end;

procedure ParsingAgainAfterAnEditKeepsTheEquality;
var P: THttpFileIncrementalParser;
begin
  RandSeed := 5;
  P := NewIncremental(RandomText(12));
  try
    P.ApplyEdit(3, 4, RandomInsert);
    P.Parse;
    P.Parse;
    AssertEqualsStr(FullParse(P.Text), Describe(P));
  finally P.Free; end;
end;

initialization
  RegisterTest('Incremental.Property', 'random edits match a full parse', RandomEditsMatchAFullParse);
  RegisterTest('Incremental.Property', 'random whole-text replacements match a full parse', RandomWholeTextReplacementsMatchAFullParse);
  RegisterTest('Incremental.Property', 'parsing again after an edit keeps the equality', ParsingAgainAfterAnEditKeepsTheEquality);
end.
