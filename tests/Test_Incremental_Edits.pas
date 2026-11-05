unit Test_Incremental_Edits;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestIncrementalHelpers, HttpFileParser, HttpFileAST,
  HttpFileResponses, HttpFileIncrementalParser;

function SixRequests: string;
var I: Integer;
begin
  Result := '';
  for I := 1 to 6 do
    Result := Result + '### r' + IntToStr(I) + #10 + 'GET http://x/' + IntToStr(I) + #10;
end;

procedure SameTextChangesNothing;
var P: THttpFileIncrementalParser; Before: string;
begin
  P := NewIncremental(SixRequests);
  try
    Before := Describe(P);
    P.SetText(SixRequests);
    AssertEqualsInt(6, P.LastReparsedCount);
    AssertEqualsStr(Before, Describe(P));
  finally P.Free; end;
end;

procedure EditInOneSegmentReparsesOnlyItAndItsPredecessor;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(SixRequests);
  try
    P.Parse;
    P.SetText(StringReplace(SixRequests, 'http://x/3', 'http://x/33', []));
    AssertEqualsInt(2, P.LastReparsedCount);
    AssertEqualsInt(4, P.LastReusedCount);
    AssertEqualsStr(FullParse(P.Text), Describe(P));
    AssertEqualsStr('http://x/33', P.HttpFile.Endpoints[2].Url);
  finally P.Free; end;
end;

procedure InsertingAboveShiftsTheRowsBelow;
var P: THttpFileIncrementalParser; RowBefore: Integer;
begin
  P := NewIncremental(SixRequests);
  try
    RowBefore := P.HttpFile.Endpoints[5].Row;
    P.ApplyEdit(1, 0, '@v = 1'#10'# note'#10);
    AssertEqualsInt(RowBefore + 2, P.HttpFile.Endpoints[5].Row);
    AssertEqualsStr(FullParse(P.Text), Describe(P));
  finally P.Free; end;
end;

procedure DeletingASeparatorMergesTwoSegments;
var P: THttpFileIncrementalParser; Count: Integer;
begin
  P := NewIncremental(SixRequests);
  try
    P.Parse;
    Count := P.SegmentCount;
    P.ApplyEdit(Pos('### r3', P.Text), Length('### r3'#10), '');
    AssertEqualsInt(Count - 1, P.SegmentCount);
    AssertEqualsStr(FullParse(P.Text), Describe(P));
  finally P.Free; end;
end;

procedure InsertingASeparatorSplitsASegment;
var P: THttpFileIncrementalParser; Count: Integer;
begin
  P := NewIncremental(Lines(['### a', 'GET http://x', '', 'GET http://y']));
  try
    P.Parse;
    Count := P.SegmentCount;
    P.ApplyEdit(Pos('GET http://y', P.Text), 0, '###'#10);
    AssertEqualsInt(Count + 1, P.SegmentCount);
    AssertEqualsStr(FullParse(P.Text), Describe(P));
  finally P.Free; end;
end;

procedure AppendingChunksMatchesAFullParseAtEveryStep;
var P: THttpFileIncrementalParser; Source: string; I: Integer;
begin
  Source := Lines(['@a = 1', '### One', 'POST http://x/{{a}}', 'Accept: a/b', '', '{"k":1}', '',
    '# @name two', 'GET http://y', '# @name three', 'DELETE http://z']);
  P := NewIncremental('');
  try
    for I := 1 to Length(Source) do
    begin
      P.Append(Source[I]);
      AssertEqualsStr(FullParse(P.Text), Describe(P), 'after ' + IntToStr(I) + ' characters');
    end;
    AssertEqualsStr(Source, P.Text);
  finally P.Free; end;
end;

procedure EditPositionIsValidated;
var P: THttpFileIncrementalParser; Raised: Boolean;
begin
  P := NewIncremental('GET http://x');
  try
    Raised := False;
    try P.ApplyEdit(99, 0, 'x'); except on ERangeError do Raised := True; end;
    AssertTrue(Raised);
  finally P.Free; end;
end;

procedure DeleteCountIsClippedToTheText;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental('GET http://x'#10'GET http://y');
  try
    P.ApplyEdit(14, 999, '');
    AssertEqualsStr('GET http://x'#10, P.Text);
    AssertEqualsStr(FullParse(P.Text), Describe(P));
  finally P.Free; end;
end;

procedure ResetForcesAFullParse;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(SixRequests);
  try
    P.Parse;
    P.Reset;
    AssertEqualsInt(0, P.SegmentCount);
    AssertEqualsStr(FullParse(SixRequests), Describe(P));
    AssertEqualsInt(6, P.LastReparsedCount);
  finally P.Free; end;
end;

initialization
  RegisterTest('Incremental.Edits', 'same text changes nothing', SameTextChangesNothing);
  RegisterTest('Incremental.Edits', 'edit in one segment reparses only it and its predecessor', EditInOneSegmentReparsesOnlyItAndItsPredecessor);
  RegisterTest('Incremental.Edits', 'inserting above shifts the rows below', InsertingAboveShiftsTheRowsBelow);
  RegisterTest('Incremental.Edits', 'deleting a separator merges two segments', DeletingASeparatorMergesTwoSegments);
  RegisterTest('Incremental.Edits', 'inserting a separator splits a segment', InsertingASeparatorSplitsASegment);
  RegisterTest('Incremental.Edits', 'appending chunks matches a full parse at every step', AppendingChunksMatchesAFullParseAtEveryStep);
  RegisterTest('Incremental.Edits', 'edit position is validated', EditPositionIsValidated);
  RegisterTest('Incremental.Edits', 'delete count is clipped to the text', DeleteCountIsClippedToTheText);
  RegisterTest('Incremental.Edits', 'Reset forces a full parse', ResetForcesAFullParse);
end.
