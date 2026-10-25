{ JsonWriter - minimal pretty printing JSON writer (no dependencies).
  Shared by every generator that emits JSON (Postman today, Insomnia etc. later). }
unit JsonWriter;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils;

type
  TJsonWriter = class
  private
    FText: string;
    FCounts: array of Integer; // items written per open container
    FAfterName: Boolean;
    procedure NewLine;
    procedure Separate;
    procedure BeforeValue;
    procedure Push;
    function Pop: Boolean; // True when the container had items
  public
    procedure BeginObject;
    procedure EndObject;
    procedure BeginArray;
    procedure EndArray;
    procedure WriteName(const AKey: string);
    procedure WriteString(const AValue: string);
    procedure WriteBoolean(AValue: Boolean);
    { convenience: "key": "value" }
    procedure WriteProperty(const AKey, AValue: string);
    function AsText: string;
  end;

function JsonEscape(const AValue: string): string;

implementation

function JsonEscape(const AValue: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(AValue) do
  begin
    C := AValue[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if C < ' ' then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
end;

procedure TJsonWriter.NewLine;
var
  I: Integer;
begin
  FText := FText + #10;
  for I := 1 to Length(FCounts) * 2 do
    FText := FText + ' ';
end;

procedure TJsonWriter.Separate;
begin
  if Length(FCounts) = 0 then
    Exit;
  if FCounts[High(FCounts)] > 0 then
    FText := FText + ',';
  Inc(FCounts[High(FCounts)]);
  NewLine;
end;

procedure TJsonWriter.BeforeValue;
begin
  if FAfterName then
    FAfterName := False
  else
    Separate;
end;

procedure TJsonWriter.Push;
begin
  SetLength(FCounts, Length(FCounts) + 1);
  FCounts[High(FCounts)] := 0;
end;

function TJsonWriter.Pop: Boolean;
begin
  Result := FCounts[High(FCounts)] > 0;
  SetLength(FCounts, Length(FCounts) - 1);
end;

procedure TJsonWriter.BeginObject;
begin
  BeforeValue;
  FText := FText + '{';
  Push;
end;

procedure TJsonWriter.EndObject;
begin
  if Pop then
    NewLine;
  FText := FText + '}';
end;

procedure TJsonWriter.BeginArray;
begin
  BeforeValue;
  FText := FText + '[';
  Push;
end;

procedure TJsonWriter.EndArray;
begin
  if Pop then
    NewLine;
  FText := FText + ']';
end;

procedure TJsonWriter.WriteName(const AKey: string);
begin
  Separate;
  FText := FText + '"' + JsonEscape(AKey) + '": ';
  FAfterName := True;
end;

procedure TJsonWriter.WriteString(const AValue: string);
begin
  BeforeValue;
  FText := FText + '"' + JsonEscape(AValue) + '"';
end;

procedure TJsonWriter.WriteBoolean(AValue: Boolean);
begin
  BeforeValue;
  if AValue then
    FText := FText + 'true'
  else
    FText := FText + 'false';
end;

procedure TJsonWriter.WriteProperty(const AKey, AValue: string);
begin
  WriteName(AKey);
  WriteString(AValue);
end;

function TJsonWriter.AsText: string;
begin
  Result := FText;
end;

end.
