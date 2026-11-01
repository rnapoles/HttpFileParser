(* HttpFilePrinter - writes a THttpFile back as canonical .http text.

  Layout:
      @name = value          every variable first, names aligned on the "="
      (blank line)
      ###                    one block per request, separated by a blank line
      # @name requestName
      VERB url [HTTP/x.y]
      Header: value
      (blank line)
      body or "< file"

  Raw values are printed by default, so {{variables}} and {{functions}} are
  kept and printing is stable: parse(print(x)) prints the same text again.
  Resolved = True prints the resolved values instead (the text a client would
  send). Variables move to the top because they are global to the file.
  Comments and stored responses are not part of the AST and are not printed.
  The HTTP version is only written when it is not HTTP/1.1. *)
unit HttpFilePrinter;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, Classes, HttpFileAST;

type
  THttpFilePrinter = class
  private
    FResolved: Boolean;
    FAlignVariables: Boolean;
    FExplicitVersion: Boolean;
    FLineBreak: string;
    FOutput: string;
    procedure AddLine(const ALine: string);
    function Body(const AText: string): string;
    procedure PrintVariables(AFile: THttpFile);
    procedure PrintEndpoint(AEndpoint: TEndpoint);
  public
    constructor Create;
    function Print(AFile: THttpFile): string;
    { UTF-8, no BOM }
    procedure SaveToFile(AFile: THttpFile; const AFileName: string);
    { print the resolved values instead of the raw text (default False) }
    property Resolved: Boolean read FResolved write FResolved;
    { pad variable names so the "=" signs line up (default True) }
    property AlignVariables: Boolean read FAlignVariables write FAlignVariables;
    { also write HTTP/1.1 (default False) }
    property ExplicitVersion: Boolean read FExplicitVersion write FExplicitVersion;
    { default LF; use #13#10 for Windows files }
    property LineBreak: string read FLineBreak write FLineBreak;
  end;

implementation

constructor THttpFilePrinter.Create;
begin
  inherited Create;
  FAlignVariables := True;
  FLineBreak := #10;
end;

procedure THttpFilePrinter.AddLine(const ALine: string);
begin
  FOutput := FOutput + ALine + FLineBreak;
end;

function THttpFilePrinter.Body(const AText: string): string;
begin
  // bodies are held with LF line breaks
  if FLineBreak = #10 then
    Result := AText
  else
    Result := StringReplace(AText, #10, FLineBreak, [rfReplaceAll]);
end;

procedure THttpFilePrinter.PrintVariables(AFile: THttpFile);
var
  I, Width: Integer;
  V: TVariable;
  Name, Value: string;
begin
  Width := 0;
  if FAlignVariables then
    for I := 0 to High(AFile.Variables) do
      if Length(AFile.Variables[I].Name) > Width then
        Width := Length(AFile.Variables[I].Name);
  for I := 0 to High(AFile.Variables) do
  begin
    V := AFile.Variables[I];
    Name := V.Name;
    while Length(Name) < Width do
      Name := Name + ' ';
    if FResolved then
      Value := V.Value
    else
      Value := V.RawValue;
    if Value = '' then
      AddLine('@' + Name + ' =')
    else
      AddLine('@' + Name + ' = ' + Value);
  end;
end;

procedure THttpFilePrinter.PrintEndpoint(AEndpoint: TEndpoint);
var
  I: Integer;
  Line, Url, Value: string;
  Header: TRequestHeader;
begin
  AddLine('###');
  if AEndpoint.Name <> '' then
    AddLine('# @name ' + AEndpoint.Name);

  if FResolved then
    Url := AEndpoint.Url
  else
    Url := AEndpoint.RawUrl;
  Line := AEndpoint.Verb + ' ' + Url;
  if FExplicitVersion or ((AEndpoint.HttpRevision <> '') and (AEndpoint.HttpRevision <> 'HTTP/1.1')) then
    Line := Line + ' ' + AEndpoint.HttpRevision;
  AddLine(Line);

  for I := 0 to High(AEndpoint.RequestHeaders) do
  begin
    Header := AEndpoint.RequestHeaders[I];
    if FResolved then
      Value := Header.Value
    else
      Value := Header.RawValue;
    if Value = '' then
      AddLine(Header.Name + ':')
    else
      AddLine(Header.Name + ': ' + Value);
  end;

  if AEndpoint.BodyFilePath <> '' then
  begin
    AddLine('');
    if FResolved then
      AddLine('< ' + AEndpoint.BodyFilePath)
    else
      AddLine(Body(AEndpoint.RawRequestBody)); // the "< path" line as written
  end
  else if AEndpoint.RawRequestBody <> '' then
  begin
    AddLine('');
    if FResolved then
      AddLine(Body(AEndpoint.RequestBody))
    else
      AddLine(Body(AEndpoint.RawRequestBody));
  end;
end;

function THttpFilePrinter.Print(AFile: THttpFile): string;
var
  I: Integer;
begin
  FOutput := '';
  PrintVariables(AFile);
  for I := 0 to High(AFile.Endpoints) do
  begin
    if FOutput <> '' then
      AddLine('');
    PrintEndpoint(AFile.Endpoints[I]);
  end;
  Result := FOutput;
end;

procedure THttpFilePrinter.SaveToFile(AFile: THttpFile; const AFileName: string);
var
  Stream: TFileStream;
  Data: RawByteString;
begin
  {$IFDEF FPC}
  Data := Print(AFile);   // FPC strings already hold UTF-8 bytes
  {$ELSE}
  Data := UTF8Encode(Print(AFile));
  {$ENDIF}
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(Data) > 0 then
      Stream.WriteBuffer(Data[1], Length(Data));
  finally
    Stream.Free;
  end;
end;

end.
