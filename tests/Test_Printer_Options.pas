unit Test_Printer_Options;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFilePrinter;

function Print(const ASource: string; AConfigure: Integer): string;
var P: THttpFileParser; Printer: THttpFilePrinter;
begin
  P := NewParser(ASource);
  Printer := THttpFilePrinter.Create;
  try
    case AConfigure of
      1: Printer.AlignVariables := False;
      2: Printer.ExplicitVersion := True;
      3: Printer.LineBreak := #13#10;
    end;
    Result := Printer.Print(P.HttpFile);
  finally Printer.Free; P.Free; end;
end;

procedure AlignmentCanBeSwitchedOff;
begin
  AssertEqualsStr(Lines(['@baseUrl = a', '@id = b', '']), Print(Lines(['@baseUrl = a', '@id = b']), 1));
end;

procedure ExplicitVersionWritesHttp11;
begin
  AssertEqualsStr(Lines(['###', 'GET http://a HTTP/1.1', '']), Print('GET http://a', 2));
end;

procedure CrLfAppliesToBodiesToo;
begin
  AssertEqualsStr('###'#13#10'POST http://a'#13#10#13#10'one'#13#10'two'#13#10,
    Print(Lines(['POST http://a', '', 'one', 'two']), 3));
end;

procedure SavesAUtf8File;
var P: THttpFileParser; Printer: THttpFilePrinter; F: TStringList;
begin
  P := NewParser('GET http://a');
  Printer := THttpFilePrinter.Create;
  F := TStringList.Create;
  try
    Printer.SaveToFile(P.HttpFile, 'printer_fixture.http');
    F.LoadFromFile('printer_fixture.http');
    AssertEqualsInt(2, F.Count);
    AssertEqualsStr('GET http://a', F[1]);
  finally F.Free; Printer.Free; P.Free; DeleteFile('printer_fixture.http'); end;
end;

initialization
  RegisterTest('Printer.Options', 'alignment can be switched off', AlignmentCanBeSwitchedOff);
  RegisterTest('Printer.Options', 'explicit version writes HTTP/1.1', ExplicitVersionWritesHttp11);
  RegisterTest('Printer.Options', 'CRLF applies to bodies too', CrLfAppliesToBodiesToo);
  RegisterTest('Printer.Options', 'saves a UTF-8 file', SavesAUtf8File);
end.
