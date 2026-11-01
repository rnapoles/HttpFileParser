unit Test_Printer_Layout;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, Classes, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFilePrinter;

function PrintSource(const ASource: string; AResolved: Boolean = False): string;
var P: THttpFileParser; Printer: THttpFilePrinter;
begin
  P := NewParser(ASource);
  Printer := THttpFilePrinter.Create;
  try
    Printer.Resolved := AResolved;
    Result := Printer.Print(P.HttpFile);
  finally Printer.Free; P.Free; end;
end;

procedure PrintsVariablesAndRequestBlocks;
begin
  AssertEqualsStr(
    Lines(['@baseUrl = http://h', '@id      = 7', '', '###', '# @name login', 'POST {{baseUrl}}/a',
      'Content-Type: application/json', '', '{"a":{{id}}}', '']),
    PrintSource(Lines(['@baseUrl = http://h', '@id = 7', '# @name login', 'POST {{baseUrl}}/a',
      'Content-Type: application/json', '', '{"a":{{id}}}'])));
end;

procedure SeparatesRequestsWithABlankLine;
begin
  AssertEqualsStr(Lines(['###', 'GET http://a', '', '###', 'DELETE http://b', '']),
    PrintSource(Lines(['GET http://a', '', 'DELETE http://b'])));
end;

procedure WritesTheVersionOnlyWhenItIsNotDefault;
begin
  AssertEqualsStr(Lines(['###', 'GET http://a HTTP/1.0', '', '###', 'GET http://b', '']),
    PrintSource(Lines(['GET http://a HTTP/1.0', '', 'GET http://b HTTP/1.1'])));
end;

procedure ResolvedModePrintsTheSentText;
begin
  AssertEqualsStr(Lines(['@h = http://z', '', '###', 'GET http://z/a', 'X-A: http://z', '']),
    PrintSource(Lines(['@h = http://z', 'GET {{h}}/a', 'X-A: {{h}}']), True));
end;

procedure FileBodyKeepsItsReference;
begin
  AssertEqualsStr(Lines(['###', 'POST http://a', '', '< ./a.xml # note', '']),
    PrintSource(Lines(['POST http://a', '', '< ./a.xml # note'])));
  AssertEqualsStr(Lines(['###', 'POST http://a', '', '< ./a.xml', '']),
    PrintSource(Lines(['POST http://a', '', '< ./a.xml # note']), True));
end;

procedure EmptyHeaderValueKeepsItsColon;
begin
  AssertEqualsStr(Lines(['###', 'GET http://a', 'X-Empty:', '']),
    PrintSource(Lines(['GET http://a', 'X-Empty:'])));
end;

procedure EmptyFilePrintsNothing;
begin
  AssertEqualsStr('', PrintSource(''));
end;

initialization
  RegisterTest('Printer.Layout', 'prints variables and request blocks', PrintsVariablesAndRequestBlocks);
  RegisterTest('Printer.Layout', 'separates requests with a blank line', SeparatesRequestsWithABlankLine);
  RegisterTest('Printer.Layout', 'writes the version only when it is not the default', WritesTheVersionOnlyWhenItIsNotDefault);
  RegisterTest('Printer.Layout', 'resolved mode prints the sent text', ResolvedModePrintsTheSentText);
  RegisterTest('Printer.Layout', 'file body keeps its reference', FileBodyKeepsItsReference);
  RegisterTest('Printer.Layout', 'empty header value keeps its colon', EmptyHeaderValueKeepsItsColon);
  RegisterTest('Printer.Layout', 'empty file prints nothing', EmptyFilePrintsNothing);
end.
