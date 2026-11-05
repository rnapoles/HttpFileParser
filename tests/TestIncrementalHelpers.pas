unit TestIncrementalHelpers;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
interface
uses SysUtils, HttpFileAST, HttpFileParser, HttpFileIncrementalParser, TestHelpers;

function NewIncremental(const ASource: string): THttpFileIncrementalParser;
{ everything the parser produced as text: variables, endpoints (raw and resolved) and diagnostics }
function Describe(AParser: THttpFileParser): string;
{ Describe of a fresh full parse of AText }
function FullParse(const AText: string): string;

implementation

function NewIncremental(const ASource: string): THttpFileIncrementalParser;
begin
  Result := THttpFileIncrementalParser.Create(ASource);
  Result.Context.SetFixedNow(FixedNowUtc, 0);
end;

function Describe(AParser: THttpFileParser): string;
var
  I, J: Integer;
  V: TVariable;
  E: TEndpoint;
  H: TRequestHeader;
  Item: THttpParseError;
begin
  Result := '';
  for I := 0 to High(AParser.HttpFile.Variables) do
  begin
    V := AParser.HttpFile.Variables[I];
    Result := Result + Format('V %s|%s|%s|%d|%d|%d'#10,
      [V.Name, V.RawValue, V.Value, V.Row, V.Column, V.ValueColumn]);
  end;
  for I := 0 to High(AParser.HttpFile.Endpoints) do
  begin
    E := AParser.HttpFile.Endpoints[I];
    Result := Result + Format('E %s|%s|%s|%s|%s|%d|%d|%d|%d|%s|%s|%s|%s'#10,
      [E.Name, E.Verb, E.Url, E.RawUrl, E.HttpRevision, E.Row, E.Column, E.UrlColumn, E.BodyRow,
       E.BodyFilePath, E.RawBodyFilePath, E.RawRequestBody, E.RequestBody]);
    for J := 0 to High(E.RequestHeaders) do
    begin
      H := E.RequestHeaders[J];
      Result := Result + Format('H %s|%s|%s|%d|%d|%d'#10,
        [H.Name, H.RawValue, H.Value, H.Row, H.Column, H.ValueColumn]);
    end;
    Result := Result + Format('R %d|%s|%s|%d'#10,
      [E.ResponseStatusCode, E.ResponseStatusText, E.ResponseBody, Length(E.ResponseHeaders)]);
  end;
  for I := 0 to AParser.Errors.Count - 1 do
  begin
    Item := AParser.Errors[I];
    Result := Result + Format('D %s|%d|%d|%d|%d|%s|%s|%s'#10,
      [SeverityName(Item.Severity), Item.Row, Item.Column, Item.EndRow, Item.EndColumn,
       Item.Rule, Item.Message, Item.Token]);
  end;
end;

function FullParse(const AText: string): string;
var P: THttpFileParser;
begin
  P := NewParser(AText);
  try Result := Describe(P); finally P.Free; end;
end;

end.
