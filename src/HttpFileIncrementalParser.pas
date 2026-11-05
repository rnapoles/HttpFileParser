(* HttpFileIncrementalParser - a THttpFileParser that re-parses only what an edit touched.

  The text is cut into SEGMENTS at lines where the parser's state is known to
  start fresh:
    - every "###" separator line
    - every "# @name x" line that names a request
  A segment (a block of lines from one boundary to the next) is parsed on its
  own and cached. An edit finds the segments it touches (plus the one before,
  because deleting a boundary line merges two segments), cuts that stretch of
  text again, parses the new segments and keeps all the others. Cached
  segments below the edit are only moved (their rows shift); nothing is lexed
  again. The global pass (variables, functions, references, stored responses)
  always runs on the whole file, because any variable may be used anywhere.
  The result is identical to a full parse of the same text.

  A "< {%" script is skipped by the parser up to its closing marker even when
  that block contains "# @name" lines, so the cutting ignores such lines too.

  Use:
      Parser.SetText(NewText)                  whole new text (the difference is found)
      Parser.ApplyEdit(Start, Deleted, Text)   what an editor reports, 1-based chars
      Parser.Append(Chunk)                     streaming input
      Parser.HttpFile / Parser.Errors          parse lazily, as before
  Parse (also called by the request executor after each response) reuses every
  segment and only repeats the global pass.

  As with any re-parse, nodes of an earlier result (TEndpoint, ...) must not be
  kept across an edit: the cached ones are reused and moved, the others freed.
  The text has no byte order mark (it is removed); offsets refer to that text. *)
unit HttpFileIncrementalParser;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, HttpFileLexer, HttpFileAST, HttpFileParser;

type
  { lines from one boundary to the next, parsed on their own }
  THttpFileSegment = class
  private
    FStart: Integer;    // 1-based offset of the first character in the text
    FLength: Integer;
    FFirstRow: Integer;
    FRowCount: Integer;
    FPart: THttpFile;   // what the segment parsed to; owns the nodes
    FErrors: THttpParseErrorList; // syntax diagnostics of the segment
  public
    constructor Create(AStart, ALength, AFirstRow, ARowCount: Integer);
    destructor Destroy; override;
    { the text moved by ACharDelta characters and ARowDelta rows }
    procedure ShiftBy(ACharDelta, ARowDelta: Integer);
    property Start: Integer read FStart;
    property Length: Integer read FLength;
    property FirstRow: Integer read FFirstRow;
    property RowCount: Integer read FRowCount;
    property Part: THttpFile read FPart;
    property Errors: THttpParseErrorList read FErrors;
  end;

  THttpFileIncrementalParser = class(THttpFileParser)
  private
    FSegments: array of THttpFileSegment;
    FBuilt: Boolean;
    FLastReparsed: Integer;
    FLastReused: Integer;
    function GetSegmentCount: Integer;
    function GetSegment(AIndex: Integer): THttpFileSegment;
    function SegmentIndexAt(APosition: Integer): Integer;
    function CreateSegment(AStart, ALength, AFirstRow, ARowCount: Integer): THttpFileSegment;
    procedure ClearSegments;
    procedure DropHttpFile;
    procedure BuildAll;
    procedure ReplaceRegion(AEditStart, AEditEnd, ADelta: Integer);
    procedure Assemble;
  public
    destructor Destroy; override;
    { full parse the first time, afterwards only the global pass }
    procedure Parse; override;
    { replaces the text; only the part that differs is parsed again }
    procedure SetText(const AText: string);
    { deletes ADeleteCount characters at AStart (1-based) and inserts AInsert there }
    procedure ApplyEdit(AStart, ADeleteCount: Integer; const AInsert: string);
    procedure Append(const AChunk: string);
    { forgets the cache: the next Parse is a full parse }
    procedure Reset;
    property Text: string read FInput;
    property SegmentCount: Integer read GetSegmentCount;
    property Segments[AIndex: Integer]: THttpFileSegment read GetSegment;
    { how many segments the latest update parsed, and how many it kept }
    property LastReparsedCount: Integer read FLastReparsed;
    property LastReusedCount: Integer read FLastReused;
  end;

implementation

type
  TSegmentSpan = record
    Start: Integer;   // 1-based, relative to the text that was cut
    Length: Integer;
    FirstRow: Integer;
    RowCount: Integer;
  end;

  TSegmentSpanArray = array of TSegmentSpan;

function StripBom(const AText: string): string;
begin
  Result := AText;
  {$IFDEF FPC}
  if Copy(Result, 1, 3) = #$EF#$BB#$BF then
    Delete(Result, 1, 3);
  {$ELSE}
  if (Length(Result) > 0) and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
  {$ENDIF}
end;

(* Cuts AText into segments. Mirrors the parser: a script block that is still open
  swallows the lines after it (they are never boundaries) until "%}" or a separator.
  AOpenScript tells whether the text ends inside such a block. *)
procedure SplitSegments(const AText: string; AFirstRow: Integer; out ASpans: TSegmentSpanArray;
  out AOpenScript: Boolean);
var
  Lexer: THttpFileLexer;
  Token: THttpToken;
  Current: TSegmentSpan;
  LineStart, OpenAt: Integer;
  InScript, Boundary: Boolean;
begin
  ASpans := nil;
  AOpenScript := False;
  Current.Start := 1;
  Current.Length := 0;
  Current.FirstRow := AFirstRow;
  Current.RowCount := 0;
  InScript := False;
  Lexer := THttpFileLexer.Create(AText, AFirstRow);
  try
    while True do
    begin
      LineStart := Lexer.Position;
      Token := Lexer.NextToken;
      if Token.Kind = tkEOF then
        Break;
      Boundary := False;
      if Token.Kind = tkSeparator then
      begin
        InScript := False;
        Boundary := True;
      end
      else if InScript then
        InScript := Pos('%}', Token.Raw) = 0
      else if Token.Kind = tkScript then
      begin
        OpenAt := Pos('{%', Token.Raw);
        InScript := Pos('%}', Copy(Token.Raw, OpenAt + 2, MaxInt)) = 0;
      end
      else if (Token.Kind = tkMetaName) and (Token.Name <> '') then
        Boundary := True;

      if Boundary and (Current.RowCount > 0) then
      begin
        Current.Length := LineStart - Current.Start;
        SetLength(ASpans, System.Length(ASpans) + 1);
        ASpans[High(ASpans)] := Current;
        Current.Start := LineStart;
        Current.FirstRow := Token.Row;
        Current.RowCount := 0;
      end;
      Inc(Current.RowCount);
    end;
    if Current.RowCount > 0 then
    begin
      Current.Length := System.Length(AText) + 1 - Current.Start;
      SetLength(ASpans, System.Length(ASpans) + 1);
      ASpans[High(ASpans)] := Current;
    end;
  finally
    Lexer.Free;
  end;
  AOpenScript := InScript;
end;

{ THttpFileSegment }

constructor THttpFileSegment.Create(AStart, ALength, AFirstRow, ARowCount: Integer);
begin
  inherited Create;
  FStart := AStart;
  FLength := ALength;
  FFirstRow := AFirstRow;
  FRowCount := ARowCount;
  FPart := THttpFile.Create;
  FErrors := THttpParseErrorList.Create;
end;

destructor THttpFileSegment.Destroy;
begin
  FErrors.Free;
  FPart.Free;
  inherited Destroy;
end;

procedure THttpFileSegment.ShiftBy(ACharDelta, ARowDelta: Integer);
var
  I: Integer;
begin
  Inc(FStart, ACharDelta);
  if ARowDelta = 0 then
    Exit;
  Inc(FFirstRow, ARowDelta);
  for I := 0 to High(FPart.Variables) do
    FPart.Variables[I].ShiftRows(ARowDelta);
  for I := 0 to High(FPart.Endpoints) do
    FPart.Endpoints[I].ShiftRows(ARowDelta);
  FErrors.ShiftRows(ARowDelta);
end;

{ THttpFileIncrementalParser }

destructor THttpFileIncrementalParser.Destroy;
begin
  ClearSegments; // frees the assembled file first: it only lists the nodes the segments own
  inherited Destroy;
end;

function THttpFileIncrementalParser.GetSegmentCount: Integer;
begin
  Result := System.Length(FSegments);
end;

function THttpFileIncrementalParser.GetSegment(AIndex: Integer): THttpFileSegment;
begin
  Result := FSegments[AIndex];
end;

procedure THttpFileIncrementalParser.DropHttpFile;
begin
  ReplaceHttpFile(nil);
  FParsed := False;
end;

procedure THttpFileIncrementalParser.ClearSegments;
var
  I: Integer;
begin
  DropHttpFile;
  for I := 0 to High(FSegments) do
    FSegments[I].Free;
  FSegments := nil;
  FBuilt := False;
end;

function THttpFileIncrementalParser.SegmentIndexAt(APosition: Integer): Integer;
var
  Low, High_, Middle: Integer;
begin
  // the last segment that starts at or before APosition
  Low := 0;
  High_ := System.Length(FSegments) - 1;
  Result := 0;
  while Low <= High_ do
  begin
    Middle := (Low + High_) div 2;
    if FSegments[Middle].Start <= APosition then
    begin
      Result := Middle;
      Low := Middle + 1;
    end
    else
      High_ := Middle - 1;
  end;
end;

function THttpFileIncrementalParser.CreateSegment(AStart, ALength, AFirstRow,
  ARowCount: Integer): THttpFileSegment;
begin
  Result := THttpFileSegment.Create(AStart, ALength, AFirstRow, ARowCount);
  try
    ParseSyntax(Copy(FInput, AStart, ALength), AFirstRow, Result.Part, Result.Errors);
  except
    Result.Free;
    raise;
  end;
end;

procedure THttpFileIncrementalParser.BuildAll;
var
  Spans: TSegmentSpanArray;
  OpenScript: Boolean;
  I: Integer;
begin
  ClearSegments;
  FInput := StripBom(FInput);
  SplitSegments(FInput, 1, Spans, OpenScript);
  SetLength(FSegments, System.Length(Spans)); // nil entries until each one is parsed
  for I := 0 to High(Spans) do
    FSegments[I] := CreateSegment(Spans[I].Start, Spans[I].Length, Spans[I].FirstRow,
      Spans[I].RowCount);
  FBuilt := True;
  FLastReparsed := System.Length(FSegments);
  FLastReused := 0;
end;

{ The edit replaced the old range [AEditStart, AEditEnd) and changed the text length by
  ADelta. FInput already holds the new text; the segments still describe the old one. }
procedure THttpFileIncrementalParser.ReplaceRegion(AEditStart, AEditEnd, ADelta: Integer);
var
  First, Last, Lo, Hi, I, J, OldRows, NewRows, RegionStart, RegionOldEnd, Last_: Integer;
  Spans: TSegmentSpanArray;
  OpenScript: Boolean;
  Fresh, Merged: array of THttpFileSegment;
begin
  if System.Length(FSegments) = 0 then
  begin
    BuildAll;
    Exit;
  end;
  First := SegmentIndexAt(AEditStart);
  Last_ := AEditEnd - 1;
  if Last_ < AEditStart then
    Last_ := AEditStart;
  Last := SegmentIndexAt(Last_);
  Lo := First - 1; // a deleted boundary line merges a segment with the one before it
  if Lo < 0 then
    Lo := 0;
  Hi := Last;

  while True do
  begin
    RegionStart := FSegments[Lo].Start;
    RegionOldEnd := FSegments[Hi].Start + FSegments[Hi].Length;
    SplitSegments(Copy(FInput, RegionStart, RegionOldEnd + ADelta - RegionStart),
      FSegments[Lo].FirstRow, Spans, OpenScript);
    if OpenScript and (Hi < High(FSegments)) then
      Inc(Hi) // an open script block runs into the next segment
    else
      Break;
  end;

  OldRows := 0;
  for I := Lo to Hi do
    Inc(OldRows, FSegments[I].RowCount);
  NewRows := 0;
  Fresh := nil;
  SetLength(Fresh, System.Length(Spans));
  try
    for I := 0 to High(Spans) do
    begin
      Fresh[I] := CreateSegment(RegionStart + Spans[I].Start - 1, Spans[I].Length,
        Spans[I].FirstRow, Spans[I].RowCount);
      Inc(NewRows, Spans[I].RowCount);
    end;
  except
    for I := 0 to High(Fresh) do
      Fresh[I].Free; // Free on nil is fine
    raise;
  end;

  DropHttpFile; // it lists nodes that are about to be freed
  for I := Lo to Hi do
    FSegments[I].Free;
  Merged := nil;
  SetLength(Merged, Lo + System.Length(Fresh) + (System.Length(FSegments) - 1 - Hi));
  J := 0;
  for I := 0 to Lo - 1 do
  begin
    Merged[J] := FSegments[I];
    Inc(J);
  end;
  for I := 0 to High(Fresh) do
  begin
    Merged[J] := Fresh[I];
    Inc(J);
  end;
  for I := Hi + 1 to High(FSegments) do
  begin
    FSegments[I].ShiftBy(ADelta, NewRows - OldRows); // moved, not parsed again
    Merged[J] := FSegments[I];
    Inc(J);
  end;
  FSegments := Merged;
  FLastReparsed := System.Length(Fresh);
  FLastReused := System.Length(FSegments) - System.Length(Fresh);
end;

procedure THttpFileIncrementalParser.Assemble;
var
  NewFile: THttpFile;
  I, J: Integer;
  Segment: THttpFileSegment;
  Item: THttpParseError;
begin
  NewFile := THttpFile.Create;
  NewFile.OwnsNodes := False; // the segments own them
  FErrors.Clear;
  for I := 0 to High(FSegments) do
  begin
    Segment := FSegments[I];
    for J := 0 to High(Segment.Part.Variables) do
      NewFile.AdoptVariable(Segment.Part.Variables[J]);
    for J := 0 to High(Segment.Part.Endpoints) do
      NewFile.AddEndpoint(Segment.Part.Endpoints[J]);
    for J := 0 to Segment.Errors.Count - 1 do
    begin
      Item := Segment.Errors[J];
      FErrors.AddRange(Item.Severity, Item.Row, Item.Column, Item.EndRow, Item.EndColumn,
        Item.Message, Item.Token, Item.Rule);
    end;
  end;
  ReplaceHttpFile(NewFile);
end;

procedure THttpFileIncrementalParser.Parse;
begin
  if not FBuilt then
    BuildAll;
  Assemble;
  FinishParse;
end;

procedure THttpFileIncrementalParser.Reset;
begin
  ClearSegments;
end;

procedure THttpFileIncrementalParser.SetText(const AText: string);
var
  NewText: string;
  OldLen, NewLen, Limit, Prefix, Suffix: Integer;
begin
  NewText := StripBom(AText);
  if NewText = FInput then
    Exit;
  FParsed := False;
  if not FBuilt then
  begin
    FInput := NewText;
    Exit;
  end;
  OldLen := System.Length(FInput);
  NewLen := System.Length(NewText);
  Limit := OldLen;
  if NewLen < Limit then
    Limit := NewLen;
  Prefix := 1; // first position that differs
  while (Prefix <= Limit) and (FInput[Prefix] = NewText[Prefix]) do
    Inc(Prefix);
  Suffix := 0; // equal characters at the end, never overlapping the prefix
  while (Suffix < Limit - (Prefix - 1)) and
        (FInput[OldLen - Suffix] = NewText[NewLen - Suffix]) do
    Inc(Suffix);
  FInput := NewText;
  ReplaceRegion(Prefix, OldLen - Suffix + 1, NewLen - OldLen);
end;

procedure THttpFileIncrementalParser.ApplyEdit(AStart, ADeleteCount: Integer;
  const AInsert: string);
var
  Len: Integer;
begin
  Len := System.Length(FInput);
  if (AStart < 1) or (AStart > Len + 1) then
    raise ERangeError.CreateFmt('Edit position %d is outside the text (1..%d)', [AStart, Len + 1]);
  if ADeleteCount < 0 then
    ADeleteCount := 0;
  if AStart + ADeleteCount > Len + 1 then
    ADeleteCount := Len + 1 - AStart;
  if (ADeleteCount = 0) and (AInsert = '') then
    Exit;
  FInput := Copy(FInput, 1, AStart - 1) + AInsert + Copy(FInput, AStart + ADeleteCount, MaxInt);
  FParsed := False;
  if FBuilt then
    ReplaceRegion(AStart, AStart + ADeleteCount, System.Length(AInsert) - ADeleteCount);
end;

procedure THttpFileIncrementalParser.Append(const AChunk: string);
begin
  ApplyEdit(System.Length(FInput) + 1, 0, AChunk);
end;

end.
