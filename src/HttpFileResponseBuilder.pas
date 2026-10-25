(* HttpFileResponseBuilder - turns the callbacks of any transport into a
  THttpResponse. A transport feeds it raw header lines and body chunks as they
  arrive; Build parses them with THttpResponseParser.

  A new header block (a line starting with HTTP/) discards the previous one,
  so redirects and interim 1xx responses leave only the final response.
  Bodies are decoded as UTF-8 text on Delphi (FPC strings already hold the
  bytes); binary bodies are therefore not preserved. *)
unit HttpFileResponseBuilder;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, HttpFileResponses, HttpFileResponseParser;

type
  THttpResponseBuilder = class
  private
    FHeaders: RawByteString;
    FBody: RawByteString;
  public
    procedure Clear;
    { one header line as delivered by the transport (with its line break) }
    procedure AddHeaderData(AData: Pointer; ASize: Integer);
    procedure AddBodyData(AData: Pointer; ASize: Integer);
    { raises EHttpResponseError when no valid status line / headers arrived }
    function Build: THttpResponse;
  end;

function TextToBytes(const AText: string): RawByteString;
function BytesToText(const ABytes: RawByteString): string;

implementation

function TextToBytes(const AText: string): RawByteString;
begin
  {$IFDEF FPC}
  Result := AText;
  {$ELSE}
  Result := UTF8Encode(AText);
  {$ENDIF}
end;

function BytesToText(const ABytes: RawByteString): string;
begin
  {$IFDEF FPC}
  Result := ABytes;
  {$ELSE}
  Result := UTF8ToString(ABytes);
  {$ENDIF}
end;

procedure AppendBytes(var ATarget: RawByteString; AData: Pointer; ASize: Integer);
var
  OldLength: Integer;
begin
  if ASize <= 0 then
    Exit;
  OldLength := Length(ATarget);
  SetLength(ATarget, OldLength + ASize);
  Move(AData^, ATarget[OldLength + 1], ASize);
end;

procedure THttpResponseBuilder.Clear;
begin
  FHeaders := '';
  FBody := '';
end;

procedure THttpResponseBuilder.AddHeaderData(AData: Pointer; ASize: Integer);
begin
  if ASize <= 0 then
    Exit;
  if (ASize >= 5) and (UpCase(PAnsiChar(AData)[0]) = 'H') and
     (UpCase(PAnsiChar(AData)[1]) = 'T') and (UpCase(PAnsiChar(AData)[2]) = 'T') and
     (UpCase(PAnsiChar(AData)[3]) = 'P') and (PAnsiChar(AData)[4] = '/') then
  begin
    FHeaders := ''; // a new status line starts a new header block
    FBody := '';
  end;
  AppendBytes(FHeaders, AData, ASize);
end;

procedure THttpResponseBuilder.AddBodyData(AData: Pointer; ASize: Integer);
begin
  AppendBytes(FBody, AData, ASize);
end;

function THttpResponseBuilder.Build: THttpResponse;
var
  Parser: THttpResponseParser;
begin
  Parser := THttpResponseParser.Create;
  try
    Result := Parser.Parse(BytesToText(FHeaders) + BytesToText(FBody));
  finally
    Parser.Free;
  end;
end;

end.
