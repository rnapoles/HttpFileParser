unit Test_Incremental_Segments;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, TestIncrementalHelpers, HttpFileParser, HttpFileAST,
  HttpFileResponses, HttpFileIncrementalParser;

procedure CutsAtSeparatorsAndNamedRequests;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(Lines(['@a = 1', '### One', 'GET http://x', '# @name b', 'GET http://y',
    '# @name', 'GET http://z']));
  try
    P.Parse;
    AssertEqualsInt(3, P.SegmentCount);
    AssertEqualsInt(1, P.Segments[0].FirstRow);
    AssertEqualsInt(1, P.Segments[0].RowCount);
    AssertEqualsInt(2, P.Segments[1].FirstRow);
    AssertEqualsInt(2, P.Segments[1].RowCount);
    AssertEqualsInt(4, P.Segments[2].FirstRow); // "# @name" without a name is not a boundary
    AssertEqualsInt(4, P.Segments[2].RowCount);
  finally P.Free; end;
end;

procedure SegmentOffsetsFollowEachOther;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(Lines(['@a = 1', '### One', 'GET http://x']));
  try
    P.Parse;
    AssertEqualsInt(1, P.Segments[0].Start);
    AssertEqualsInt(P.Segments[0].Length + 1, P.Segments[1].Start);
    AssertEqualsInt(Length(P.Text) + 1, P.Segments[1].Start + P.Segments[1].Length);
  finally P.Free; end;
end;

procedure BoundaryOnTheFirstLineMakesNoEmptySegment;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(Lines(['### a', 'GET http://x']));
  try
    P.Parse;
    AssertEqualsInt(1, P.SegmentCount);
  finally P.Free; end;
end;

procedure OpenScriptHidesNamedRequestLines;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental(Lines(['### a', '< {%', '# @name inside', '%}', '# @name b', 'GET http://x']));
  try
    P.Parse;
    AssertEqualsInt(2, P.SegmentCount);
    AssertEqualsInt(5, P.Segments[1].FirstRow);
  finally P.Free; end;
end;

procedure EmptyTextHasNoSegments;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental('');
  try
    P.Parse;
    AssertEqualsInt(0, P.SegmentCount);
    AssertEqualsInt(0, Length(P.HttpFile.Endpoints));
  finally P.Free; end;
end;

procedure LineEndingsAreCounted;
var P: THttpFileIncrementalParser;
begin
  P := NewIncremental('@a = 1'#13#10'### s'#13#10'GET http://x'#13'GET http://y');
  try
    P.Parse;
    AssertEqualsInt(2, P.SegmentCount);
    AssertEqualsInt(2, P.Segments[1].FirstRow);
    AssertEqualsInt(3, P.Segments[1].RowCount);
    AssertEqualsStr(FullParse(P.Text), Describe(P));
  finally P.Free; end;
end;

initialization
  RegisterTest('Incremental.Segments', 'cuts at separators and named requests', CutsAtSeparatorsAndNamedRequests);
  RegisterTest('Incremental.Segments', 'segment offsets follow each other', SegmentOffsetsFollowEachOther);
  RegisterTest('Incremental.Segments', 'boundary on the first line makes no empty segment', BoundaryOnTheFirstLineMakesNoEmptySegment);
  RegisterTest('Incremental.Segments', 'open script hides named request lines', OpenScriptHidesNamedRequestLines);
  RegisterTest('Incremental.Segments', 'empty text has no segments', EmptyTextHasNoSegments);
  RegisterTest('Incremental.Segments', 'CR, LF and CRLF are counted as one line break each', LineEndingsAreCounted);
end.
