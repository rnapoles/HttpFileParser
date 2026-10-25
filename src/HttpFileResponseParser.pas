(* HttpFileResponseParser - raw HTTP responses and saved response files.

  THttpResponseParser reads one raw response:

      HTTP/1.1 200 OK            status line (HTTP/2 204 without reason is fine)
      Content-Type: text/plain   headers, "Name: value", folded lines allowed
                                 blank line
      body                       everything else, verbatim

  Interim 1xx responses (100 Continue, ...) that come before the final one are
  skipped. THttpResponseFileLoader reads a file with several saved responses,
  the layout of the REST Client "save response" files:

      ### optional title (used as the name when there is no @name)
      # @name login
      HTTP/1.1 200 OK
      X-AuthToken: abc

      {"id":7}

  Each response is stored under its request name. Line breaks of loaded bodies
  become LF and trailing blank lines are dropped. *)
unit HttpFileResponseParser;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, HttpFileAST, HttpFileResponses;

type
  EHttpResponseError = class(Exception)
  public
    Row: Integer;    // 1-based, relative to the parsed text
    Column: Integer;
    constructor CreateAt(const AMessage: string; ARow, AColumn: Integer);
  end;

  THttpResponseParser = class
  private
    FText: string;
    FPos: Integer;
    FRow: Integer;     // row of the next line
    FLineRow: Integer; // row of the line read last
    function AtEnd: Boolean;
    function ReadLine: string;
    procedure ParseStatusLine(const ALine: string; AResponse: THttpResponse);
    procedure ParseStatusAndHeaders(AResponse: THttpResponse);
  public
    { raises EHttpResponseError; the caller owns the result }
    function Parse(const AText: string): THttpResponse;
    function TryParse(const AText: string; out AResponse: THttpResponse;
      out AMessage: string): Boolean;
  end;

  THttpResponseFileLoader = class
  private
    FParser: THttpResponseParser;
    FErrors: THttpParseErrorList;
    FStore: THttpResponseStore;
    FStored: Integer;
    FSectionTitle: string;
    FSectionName: string;
    FContentRow: Integer;
    FContent: string;
    FHasContent: Boolean;
    procedure StartSection(const ATitle: string);
    procedure AddLine(const ALine: string; ARow: Integer);
    procedure FlushSection;
  public
    constructor Create;
    destructor Destroy; override;
    { returns how many responses were stored }
    function LoadFromText(const AText: string; AStore: THttpResponseStore): Integer;
    function LoadFromFile(const AFileName: string; AStore: THttpResponseStore): Integer;
    property Errors: THttpParseErrorList read FErrors;
  end;

implementation

{ EHttpResponseError }

constructor EHttpResponseError.CreateAt(const AMessage: string; ARow, AColumn: Integer);
begin
  inherited Create(AMessage);
  Row := ARow;
  Column := AColumn;
end;

{ THttpResponseParser }

function THttpResponseParser.AtEnd: Boolean;
begin
  Result := FPos > Length(FText);
end;

function THttpResponseParser.ReadLine: string;
var
  Start: Integer;
begin
  FLineRow := FRow;
  Start := FPos;
  while (FPos <= Length(FText)) and (FText[FPos] <> #10) and (FText[FPos] <> #13) do
    Inc(FPos);
  Result := Copy(FText, Start, FPos - Start);
  if FPos <= Length(FText) then
  begin
    if (FText[FPos] = #13) and (FPos < Length(FText)) and (FText[FPos + 1] = #10) then
      Inc(FPos);
    Inc(FPos);
  end;
  Inc(FRow); // also after a last line without line break
end;

procedure THttpResponseParser.ParseStatusLine(const ALine: string; AResponse: THttpResponse);
var
  Line, Rest, CodeText: string;
  P, Code: Integer;
begin
  Line := Trim(ALine);
  P := Pos(' ', Line);
  if (P = 0) or (UpperCase(Copy(Line, 1, 5)) <> 'HTTP/') then
    raise EHttpResponseError.CreateAt(
      'Invalid status line "' + Line + '" (expected "HTTP/1.1 200 OK")', FLineRow, 1);
  AResponse.HttpVersion := Copy(Line, 1, P - 1);
  Rest := TrimLeft(Copy(Line, P + 1, MaxInt));
  P := Pos(' ', Rest);
  if P = 0 then
    CodeText := Rest
  else
    CodeText := Copy(Rest, 1, P - 1);
  if (not TryStrToInt(CodeText, Code)) or (Code < 100) or (Code > 999) then
    raise EHttpResponseError.CreateAt(
      'Invalid status code "' + CodeText + '"', FLineRow, Length(AResponse.HttpVersion) + 2);
  AResponse.StatusCode := Code;
  if P = 0 then
    AResponse.StatusText := ''
  else
    AResponse.StatusText := Trim(Copy(Rest, P + 1, MaxInt));
end;

procedure THttpResponseParser.ParseStatusAndHeaders(AResponse: THttpResponse);
var
  Line: string;
  Names, Values: TStringList;
  P, I: Integer;
begin
  repeat
    if AtEnd then
      raise EHttpResponseError.CreateAt('Missing status line', FRow, 1);
    Line := ReadLine;
  until Trim(Line) <> '';
  ParseStatusLine(Line, AResponse);

  Names := TStringList.Create;
  Values := TStringList.Create;
  try
    while not AtEnd do
    begin
      Line := ReadLine;
      if Trim(Line) = '' then
        Break; // end of the header section
      if (Line[1] = ' ') or (Line[1] = #9) then
      begin
        if Names.Count = 0 then
          raise EHttpResponseError.CreateAt('Header continuation without a header', FLineRow, 1);
        Values[Values.Count - 1] := Values[Values.Count - 1] + ' ' + Trim(Line);
        Continue;
      end;
      P := Pos(':', Line);
      if P < 2 then
        raise EHttpResponseError.CreateAt(
          'Invalid header line "' + Line + '" (expected "Name: value")', FLineRow, 1);
      Names.Add(Trim(Copy(Line, 1, P - 1)));
      Values.Add(Trim(Copy(Line, P + 1, MaxInt)));
    end;
    for I := 0 to Names.Count - 1 do
      AResponse.AddHeader(Names[I], Values[I]);
  finally
    Values.Free;
    Names.Free;
  end;
end;

function THttpResponseParser.Parse(const AText: string): THttpResponse;
begin
  FText := AText;
  FPos := 1;
  FRow := 1;
  FLineRow := 1;
  Result := THttpResponse.Create;
  try
    repeat
      Result.Clear;
      ParseStatusAndHeaders(Result);
    until not ((Result.StatusCode >= 100) and (Result.StatusCode < 200) and
               (Result.StatusCode <> 101)); // skip interim responses
    Result.Body := Copy(FText, FPos, MaxInt);
  except
    Result.Free;
    raise;
  end;
end;

function THttpResponseParser.TryParse(const AText: string; out AResponse: THttpResponse;
  out AMessage: string): Boolean;
begin
  AResponse := nil;
  AMessage := '';
  try
    AResponse := Parse(AText);
    Result := True;
  except
    on E: EHttpResponseError do
    begin
      AMessage := E.Message;
      Result := False;
    end;
  end;
end;

{ THttpResponseFileLoader }

constructor THttpResponseFileLoader.Create;
begin
  inherited Create;
  FParser := THttpResponseParser.Create;
  FErrors := THttpParseErrorList.Create;
end;

destructor THttpResponseFileLoader.Destroy;
begin
  FErrors.Free;
  FParser.Free;
  inherited Destroy;
end;

procedure THttpResponseFileLoader.StartSection(const ATitle: string);
begin
  FSectionTitle := ATitle;
  FSectionName := '';
  FContent := '';
  FHasContent := False;
  FContentRow := 0;
end;

procedure THttpResponseFileLoader.AddLine(const ALine: string; ARow: Integer);
var
  Text, Name: string;
begin
  if FHasContent then
  begin
    FContent := FContent + #10 + ALine;
    Exit;
  end;
  Text := Trim(ALine);
  if Text = '' then
    Exit;
  if (Text[1] = '#') or (Copy(Text, 1, 2) = '//') then
  begin
    if Text[1] = '#' then
      Text := Trim(Copy(Text, 2, MaxInt))
    else
      Text := Trim(Copy(Text, 3, MaxInt));
    if Copy(Text, 1, 5) = '@name' then
    begin
      Name := Trim(Copy(Text, 6, MaxInt));
      if (Name <> '') and (Name[1] = '=') then
        Name := Trim(Copy(Name, 2, MaxInt));
      FSectionName := Name;
    end;
    Exit;
  end;
  FHasContent := True;
  FContentRow := ARow;
  FContent := ALine;
end;

procedure THttpResponseFileLoader.FlushSection;
var
  Name: string;
  Response, Stored: THttpResponse;
begin
  if not FHasContent then
    Exit;
  Name := FSectionName;
  if Name = '' then
    Name := FSectionTitle;
  if Name = '' then
  begin
    FErrors.Add(hsError, FContentRow, 1,
      'Saved response has no name (add "# @name <request>" or a "### <request>" title)',
      Trim(FContent), 'ResponseName');
    Exit;
  end;
  try
    Response := FParser.Parse(TrimRight(FContent));
  except
    on E: EHttpResponseError do
    begin
      FErrors.Add(hsError, FContentRow + E.Row - 1, E.Column, E.Message,
        Name, 'ResponseFormat');
      Exit;
    end;
  end;
  try
    Stored := FStore.Put(Name);
    Stored.Assign(Response);
    Inc(FStored);
  finally
    Response.Free;
  end;
end;

function THttpResponseFileLoader.LoadFromText(const AText: string;
  AStore: THttpResponseStore): Integer;
var
  I, Start, Row, Len: Integer;
  Line: string;
begin
  FStore := AStore;
  FStored := 0;
  FErrors.Clear;
  StartSection('');
  Len := Length(AText);
  Start := 1;
  Row := 1;
  I := 1;
  while Start <= Len + 1 do
  begin
    I := Start;
    while (I <= Len) and (AText[I] <> #10) and (AText[I] <> #13) do
      Inc(I);
    Line := Copy(AText, Start, I - Start);
    if (Copy(Line, 1, 3) = '###') then
    begin
      FlushSection;
      StartSection(Trim(Copy(Line, 4, MaxInt)));
    end
    else if (I <= Len) or (Line <> '') then
      AddLine(Line, Row);
    if I > Len then
      Break;
    if (AText[I] = #13) and (I < Len) and (AText[I + 1] = #10) then
      Inc(I);
    Start := I + 1;
    Inc(Row);
  end;
  FlushSection;
  Result := FStored;
end;

function THttpResponseFileLoader.LoadFromFile(const AFileName: string;
  AStore: THttpResponseStore): Integer;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    {$IFDEF FPC}
    Lines.LoadFromFile(AFileName);
    {$ELSE}
    Lines.LoadFromFile(AFileName, TEncoding.UTF8);
    {$ENDIF}
    Result := LoadFromText(Lines.Text, AStore);
  finally
    Lines.Free;
  end;
end;

end.
