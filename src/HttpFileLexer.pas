{ HttpFileLexer - lightweight line-oriented lexer for .http / .rest files.

  Character level:  PeekChar / ConsumeChar / MatchToken over FInput/FPos/FLen.
  Token level:      NextToken returns one classified logical line.

  Line classification is context free; the parser decides what a token means in
  its position (e.g. everything inside a request body is raw text). }
unit HttpFileLexer;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils;

type
  THttpTokenKind = (
    tkEOF,
    tkBlank,
    tkSeparator,         // ### title
    tkComment,           // # text   or   // text
    tkMetaName,          // # @name value   /   # @name = value
    tkVariableDecl,      // @name = value
    tkRequestLine,       // VERB url [HTTP/x]   or   http(s)://url
    tkQueryContinuation, // indented ?a=b / &c=d
    tkHeaderLine,        // Name: value
    tkFileRef,           // < path
    tkScript,            // < {% ... %}  or  > {% ... %}   (unsupported)
    tkText);

  THttpToken = record
    Kind: THttpTokenKind;
    Row: Integer;      // 1-based row of the line
    Col: Integer;      // 1-based column of first non-blank character
    Raw: string;       // complete line without line break
    Name: string;      // verb / variable name / header name / @name value
    Value: string;     // url / value / path / comment text / separator title
    Version: string;   // HTTP/x.y for request lines
    ValueCol: Integer; // 1-based column where Value starts
  end;

  TLexerMark = record
    Pos, Row, Col: Integer;
  end;

  THttpFileLexer = class
  private
    FInput: string;
    FPos: Integer;
    FLen: Integer;
    FRow: Integer;
    FCol: Integer;
    function Mark: TLexerMark;
    procedure Reset(const AMark: TLexerMark);
    function AtEOL: Boolean;
    procedure SkipSpaces;
    procedure ConsumeEOL;
    function ReadToEOL: string;
    function ReadWord: string;
    procedure ClassifyLine(var AToken: THttpToken; AIndented: Boolean);
    procedure ScanSeparator(var AToken: THttpToken);
    procedure ScanComment(var AToken: THttpToken);
    function TryScanVariableDecl(var AToken: THttpToken): Boolean;
    function TryScanScript(var AToken: THttpToken): Boolean;
    function TryScanFileRef(var AToken: THttpToken): Boolean;
    function TryScanRequestLine(var AToken: THttpToken): Boolean;
    function TryScanHeader(var AToken: THttpToken): Boolean;
  public
    constructor Create(const AInput: string);
    { character primitives }
    function AtEnd: Boolean;
    function PeekChar(AOffset: Integer = 0): Char;
    function ConsumeChar: Char; // CR, LF and CRLF are returned as #10
    function MatchToken(const AToken: string): Boolean;
    function MatchTokenIgnoreCase(const AToken: string): Boolean;
    { token level }
    function NextToken: THttpToken;
    property Row: Integer read FRow;
    property Col: Integer read FCol;
    property Position: Integer read FPos;
  end;

implementation

const
  KnownVerbs: array[0..18] of string = (
    'GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'CONNECT', 'OPTIONS', 'TRACE',
    'PATCH', 'PROPFIND', 'PROPPATCH', 'MKCOL', 'COPY', 'MOVE', 'LOCK',
    'UNLOCK', 'SEARCH', 'REPORT', 'MKCALENDAR');

function IsBlankChar(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9);
end;

function IsAlnumChar(C: Char): Boolean;
begin
  Result := ((C >= '0') and (C <= '9')) or ((C >= 'a') and (C <= 'z')) or
    ((C >= 'A') and (C <= 'Z'));
end;

function IsVariableNameChar(C: Char): Boolean;
begin
  Result := IsAlnumChar(C) or (C = '_') or (C = '-') or (C = '.');
end;

function IsHeaderNameChar(C: Char): Boolean;
begin
  Result := IsAlnumChar(C) or (Pos(C, '!#$%&''*+-.^_`|~') > 0);
end;

function IsKnownVerb(const AWord: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(KnownVerbs) to High(KnownVerbs) do
    if KnownVerbs[I] = AWord then
    begin
      Result := True;
      Exit;
    end;
end;

procedure InitToken(var AToken: THttpToken);
begin
  AToken.Kind := tkText;
  AToken.Row := 0;
  AToken.Col := 0;
  AToken.Raw := '';
  AToken.Name := '';
  AToken.Value := '';
  AToken.Version := '';
  AToken.ValueCol := 0;
end;

{ THttpFileLexer }

constructor THttpFileLexer.Create(const AInput: string);
begin
  inherited Create;
  FInput := AInput;
  {$IFDEF FPC}
  if Copy(FInput, 1, 3) = #$EF#$BB#$BF then
    Delete(FInput, 1, 3);
  {$ELSE}
  if (Length(FInput) > 0) and (FInput[1] = #$FEFF) then
    Delete(FInput, 1, 1);
  {$ENDIF}
  FLen := Length(FInput);
  FPos := 1;
  FRow := 1;
  FCol := 1;
end;

function THttpFileLexer.AtEnd: Boolean;
begin
  Result := FPos > FLen;
end;

function THttpFileLexer.PeekChar(AOffset: Integer): Char;
begin
  if (AOffset >= 0) and (FPos + AOffset <= FLen) then
    Result := FInput[FPos + AOffset]
  else
    Result := #0;
end;

function THttpFileLexer.ConsumeChar: Char;
begin
  Result := PeekChar;
  if FPos > FLen then
    Exit;
  Inc(FPos);
  if Result = #13 then
  begin
    if PeekChar = #10 then
      Inc(FPos);
    Result := #10;
    Inc(FRow);
    FCol := 1;
  end
  else if Result = #10 then
  begin
    Inc(FRow);
    FCol := 1;
  end
  else
    Inc(FCol);
end;

function THttpFileLexer.MatchToken(const AToken: string): Boolean;
var
  I: Integer;
begin
  Result := (AToken <> '') and (Copy(FInput, FPos, Length(AToken)) = AToken);
  if Result then
    for I := 1 to Length(AToken) do
      ConsumeChar;
end;

function THttpFileLexer.MatchTokenIgnoreCase(const AToken: string): Boolean;
var
  I: Integer;
begin
  Result := (AToken <> '') and SameText(Copy(FInput, FPos, Length(AToken)), AToken);
  if Result then
    for I := 1 to Length(AToken) do
      ConsumeChar;
end;

function THttpFileLexer.Mark: TLexerMark;
begin
  Result.Pos := FPos;
  Result.Row := FRow;
  Result.Col := FCol;
end;

procedure THttpFileLexer.Reset(const AMark: TLexerMark);
begin
  FPos := AMark.Pos;
  FRow := AMark.Row;
  FCol := AMark.Col;
end;

function THttpFileLexer.AtEOL: Boolean;
begin
  Result := AtEnd or (PeekChar = #10) or (PeekChar = #13);
end;

procedure THttpFileLexer.SkipSpaces;
begin
  while IsBlankChar(PeekChar) do
    ConsumeChar;
end;

procedure THttpFileLexer.ConsumeEOL;
begin
  if (not AtEnd) and AtEOL then
    ConsumeChar;
end;

function THttpFileLexer.ReadToEOL: string;
var
  Start: Integer;
begin
  Start := FPos;
  while not AtEOL do
    ConsumeChar;
  Result := Copy(FInput, Start, FPos - Start);
end;

function THttpFileLexer.ReadWord: string;
var
  Start: Integer;
begin
  Start := FPos;
  while (not AtEOL) and (not IsBlankChar(PeekChar)) do
    ConsumeChar;
  Result := Copy(FInput, Start, FPos - Start);
end;

function THttpFileLexer.NextToken: THttpToken;
var
  LineStart: Integer;
  Indented: Boolean;
begin
  InitToken(Result);
  if AtEnd then
  begin
    Result.Kind := tkEOF;
    Result.Row := FRow;
    Result.Col := FCol;
    Exit;
  end;
  LineStart := FPos;
  Result.Row := FRow;
  SkipSpaces;
  Indented := FPos > LineStart;
  Result.Col := FCol;
  ClassifyLine(Result, Indented);
  while not AtEOL do // safety net: every scanner must end at EOL
    ConsumeChar;
  Result.Raw := Copy(FInput, LineStart, FPos - LineStart);
  ConsumeEOL;
end;

procedure THttpFileLexer.ClassifyLine(var AToken: THttpToken; AIndented: Boolean);
begin
  if AtEOL then
    AToken.Kind := tkBlank
  else if (PeekChar = '#') and (PeekChar(1) = '#') and (PeekChar(2) = '#') then
    ScanSeparator(AToken)
  else if (PeekChar = '#') or ((PeekChar = '/') and (PeekChar(1) = '/')) then
    ScanComment(AToken)
  else if AIndented and ((PeekChar = '?') or (PeekChar = '&')) then
  begin
    AToken.Kind := tkQueryContinuation;
    AToken.ValueCol := FCol;
    AToken.Value := Trim(ReadToEOL);
  end
  else if (PeekChar = '@') and TryScanVariableDecl(AToken) then
  else if TryScanScript(AToken) then
  else if TryScanFileRef(AToken) then
  else if TryScanRequestLine(AToken) then
  else if TryScanHeader(AToken) then
  else
  begin
    AToken.Kind := tkText;
    AToken.ValueCol := FCol;
    AToken.Value := ReadToEOL;
  end;
end;

procedure THttpFileLexer.ScanSeparator(var AToken: THttpToken);
begin
  AToken.Kind := tkSeparator;
  while PeekChar = '#' do
    ConsumeChar;
  SkipSpaces;
  AToken.ValueCol := FCol;
  AToken.Value := Trim(ReadToEOL);
end;

procedure THttpFileLexer.ScanComment(var AToken: THttpToken);
var
  Text, Rest: string;
begin
  if PeekChar = '#' then
    ConsumeChar
  else
    MatchToken('//');
  SkipSpaces;
  AToken.ValueCol := FCol;
  Text := Trim(ReadToEOL);
  AToken.Kind := tkComment;
  AToken.Value := Text;
  if (Copy(Text, 1, 5) = '@name') and
     ((Length(Text) = 5) or IsBlankChar(Text[6]) or (Text[6] = '=')) then
  begin
    Rest := Trim(Copy(Text, 6, MaxInt));
    if (Rest <> '') and (Rest[1] = '=') then
      Rest := Trim(Copy(Rest, 2, MaxInt));
    AToken.Kind := tkMetaName;
    AToken.Name := Rest;
  end;
end;

function THttpFileLexer.TryScanVariableDecl(var AToken: THttpToken): Boolean;
var
  M: TLexerMark;
  Start: Integer;
begin
  Result := False;
  M := Mark;
  ConsumeChar; // '@'
  Start := FPos;
  while IsVariableNameChar(PeekChar) do
    ConsumeChar;
  if FPos = Start then
  begin
    Reset(M);
    Exit;
  end;
  AToken.Name := Copy(FInput, Start, FPos - Start);
  SkipSpaces;
  if PeekChar <> '=' then
  begin
    AToken.Name := '';
    Reset(M);
    Exit;
  end;
  ConsumeChar;
  SkipSpaces;
  AToken.ValueCol := FCol;
  AToken.Value := TrimRight(ReadToEOL);
  AToken.Kind := tkVariableDecl;
  Result := True;
end;

function THttpFileLexer.TryScanScript(var AToken: THttpToken): Boolean;
var
  M: TLexerMark;
  Marker: Char;
begin
  Result := False;
  Marker := PeekChar;
  if (Marker <> '<') and (Marker <> '>') then
    Exit;
  M := Mark;
  ConsumeChar;
  SkipSpaces;
  if MatchToken('{%') then
  begin
    AToken.Kind := tkScript;
    AToken.Value := Marker;
    ReadToEOL;
    Result := True;
  end
  else
    Reset(M);
end;

function THttpFileLexer.TryScanFileRef(var AToken: THttpToken): Boolean;
var
  Path: string;
  I, CommentAt: Integer;
begin
  Result := False;
  if (PeekChar <> '<') or not IsBlankChar(PeekChar(1)) then
    Exit;
  ConsumeChar;
  SkipSpaces;
  AToken.ValueCol := FCol;
  Path := ReadToEOL;
  CommentAt := 0;
  for I := 2 to Length(Path) do
    if (Path[I] = '#') and IsBlankChar(Path[I - 1]) then
    begin
      CommentAt := I;
      Break;
    end;
  if CommentAt > 0 then
    Path := Copy(Path, 1, CommentAt - 1);
  AToken.Value := Trim(Path);
  AToken.Kind := tkFileRef;
  Result := True;
end;

function THttpFileLexer.TryScanRequestLine(var AToken: THttpToken): Boolean;
var
  M: TLexerMark;
  Word, Rest, Lower, LastWord: string;
  I: Integer;
begin
  Result := False;
  M := Mark;
  Word := ReadWord;
  Lower := LowerCase(Word);
  if IsKnownVerb(Word) then
    AToken.Name := Word
  else if (Copy(Lower, 1, 7) = 'http://') or (Copy(Lower, 1, 8) = 'https://') then
  begin
    Reset(M);
    AToken.Name := 'GET';
  end
  else
  begin
    Reset(M);
    Exit;
  end;
  SkipSpaces;
  AToken.ValueCol := FCol;
  Rest := TrimRight(ReadToEOL);
  AToken.Value := Rest;
  I := Length(Rest);
  while (I > 0) and not IsBlankChar(Rest[I]) do
    Dec(I);
  if I > 0 then
  begin
    LastWord := Copy(Rest, I + 1, MaxInt);
    if UpperCase(Copy(LastWord, 1, 5)) = 'HTTP/' then
    begin
      AToken.Version := LastWord;
      AToken.Value := TrimRight(Copy(Rest, 1, I - 1));
    end;
  end;
  AToken.Kind := tkRequestLine;
  Result := True;
end;

function THttpFileLexer.TryScanHeader(var AToken: THttpToken): Boolean;
var
  M: TLexerMark;
  Start: Integer;
begin
  Result := False;
  M := Mark;
  Start := FPos;
  while IsHeaderNameChar(PeekChar) do
    ConsumeChar;
  if FPos = Start then
  begin
    Reset(M);
    Exit;
  end;
  AToken.Name := Copy(FInput, Start, FPos - Start);
  SkipSpaces;
  if PeekChar <> ':' then
  begin
    AToken.Name := '';
    Reset(M);
    Exit;
  end;
  ConsumeChar;
  SkipSpaces;
  AToken.ValueCol := FCol;
  AToken.Value := TrimRight(ReadToEOL);
  AToken.Kind := tkHeaderLine;
  Result := True;
end;

end.
