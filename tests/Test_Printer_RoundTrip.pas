unit Test_Printer_RoundTrip;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFilePrinter;

const
  Source =
    '@baseUrl = http://h'#10'@token = {{login.response.headers.X-AuthToken}}'#10#10 +
    '### Login'#10'# @name login'#10'POST {{baseUrl}}/login HTTP/1.0'#10'Content-Type: application/json'#10 +
    'X-Request-Id: {{$guid}}'#10#10'{'#10'  "user": "demo"'#10'}'#10#10 +
    '### Upload'#10'# @name upload'#10'POST {{baseUrl}}/up'#10'Authorization: Bearer {{token}}'#10#10'< ./a.xml # note'#10#10 +
    'DELETE {{baseUrl}}/x/1';

function PrintOf(const AText: string; out AErrors: Integer): string;
var P: THttpFileParser; Printer: THttpFilePrinter;
begin
  P := NewParser(AText);
  Printer := THttpFilePrinter.Create;
  try
    Result := Printer.Print(P.HttpFile);
    AErrors := P.Errors.ErrorCount;
  finally Printer.Free; P.Free; end;
end;

procedure PrintingTwiceGivesTheSameText;
var First, Second: string; E: Integer;
begin
  First := PrintOf(Source, E);
  Second := PrintOf(First, E);
  AssertEqualsStr(First, Second);
  AssertEqualsInt(0, E);
end;

procedure ReparsedFileHasTheSameStructure;
var A, B: THttpFileParser; Text: string; E: Integer; I: Integer;
begin
  Text := PrintOf(Source, E);
  A := NewParser(Source);
  B := NewParser(Text);
  try
    AssertEqualsInt(Length(A.HttpFile.Variables), Length(B.HttpFile.Variables));
    AssertEqualsInt(Length(A.HttpFile.Endpoints), Length(B.HttpFile.Endpoints));
    for I := 0 to High(A.HttpFile.Variables) do
    begin
      AssertEqualsStr(A.HttpFile.Variables[I].Name, B.HttpFile.Variables[I].Name);
      AssertEqualsStr(A.HttpFile.Variables[I].RawValue, B.HttpFile.Variables[I].RawValue);
    end;
    for I := 0 to High(A.HttpFile.Endpoints) do
    begin
      AssertEqualsStr(A.HttpFile.Endpoints[I].Name, B.HttpFile.Endpoints[I].Name);
      AssertEqualsStr(A.HttpFile.Endpoints[I].Verb, B.HttpFile.Endpoints[I].Verb);
      AssertEqualsStr(A.HttpFile.Endpoints[I].RawUrl, B.HttpFile.Endpoints[I].RawUrl);
      AssertEqualsStr(A.HttpFile.Endpoints[I].HttpRevision, B.HttpFile.Endpoints[I].HttpRevision);
      AssertEqualsStr(A.HttpFile.Endpoints[I].RawRequestBody, B.HttpFile.Endpoints[I].RawRequestBody);
      AssertEqualsInt(Length(A.HttpFile.Endpoints[I].RequestHeaders), Length(B.HttpFile.Endpoints[I].RequestHeaders));
    end;
  finally B.Free; A.Free; end;
end;

procedure TitleOnlyNamesBecomeMetadataNames;
var Text: string; E: Integer;
begin
  Text := PrintOf(Lines(['### Get All Posts', 'GET http://x']), E);
  AssertEqualsStr(Lines(['###', '# @name Get All Posts', 'GET http://x', '']), Text);
end;

initialization
  RegisterTest('Printer.RoundTrip', 'printing twice gives the same text', PrintingTwiceGivesTheSameText);
  RegisterTest('Printer.RoundTrip', 'reparsed file has the same structure', ReparsedFileHasTheSameStructure);
  RegisterTest('Printer.RoundTrip', 'title-only names become @name metadata', TitleOnlyNamesBecomeMetadataNames);
end.
