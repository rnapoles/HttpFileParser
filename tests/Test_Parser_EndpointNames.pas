unit Test_Parser_EndpointNames;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
interface
implementation
uses SysUtils, MiniTest, TestHelpers, HttpFileParser, HttpFileAST, HttpFileFunctions;

function NameOf(const ASource: string; AIndex: Integer = 0): string;
var P: THttpFileParser;
begin
  P := NewParser(ASource);
  try Result := P.HttpFile.Endpoints[AIndex].Name; finally P.Free; end;
end;

procedure NameFromMetadata;
begin
  AssertEqualsStr('first', NameOf(Lines(['# @name first', 'GET http://x'])));
end;

procedure NameFromMetadataWithEquals;
begin
  AssertEqualsStr('second', NameOf(Lines(['# @name = second', 'GET http://x'])));
end;

procedure NameFallsBackToSeparatorTitle;
begin
  AssertEqualsStr('Title text', NameOf(Lines(['### Title text', 'GET http://x'])));
end;

procedure MetadataWinsOverSeparatorTitle;
begin
  AssertEqualsStr('n', NameOf(Lines(['### T', '# @name n', 'GET http://x'])));
end;

procedure NameDoesNotLeakIntoNextRequest;
begin
  AssertEqualsStr('', NameOf(Lines(['# @name a', 'GET http://x', '', 'GET http://y']), 1));
end;

initialization
  RegisterTest('Parser.EndpointNames', 'name from metadata', NameFromMetadata);
  RegisterTest('Parser.EndpointNames', 'name from metadata with equals', NameFromMetadataWithEquals);
  RegisterTest('Parser.EndpointNames', 'name falls back to separator title', NameFallsBackToSeparatorTitle);
  RegisterTest('Parser.EndpointNames', 'metadata wins over separator title', MetadataWinsOverSeparatorTitle);
  RegisterTest('Parser.EndpointNames', 'name does not leak into next request', NameDoesNotLeakIntoNextRequest);
end.
