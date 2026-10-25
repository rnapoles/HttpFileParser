(* HttpFileReferences - syntax of request references inside double braces:

    requestName.[request|response].[body|headers].[* or JSONPath or Header Name]

  e.g. login.response.headers.X-AuthToken  or  createComment.response.body.$.id

  The request name is matched against the endpoints of the file (names may
  contain dots, scope and part are case-insensitive). Text that does not start
  with a known request name is not a reference at all (it may be a variable
  or a registered object). A known request name with a malformed rest is
  reported as invalid. *)
unit HttpFileReferences;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, StrUtils, HttpFileAST;

type
  TReferenceScope = (rsRequest, rsResponse);
  TReferencePart = (rpBody, rpHeaders);
  TReferenceMatch = (rmNotAReference, rmValid, rmInvalid);

  TRequestReference = record
    RequestName: string;
    Scope: TReferenceScope;
    Part: TReferencePart;
    Selector: string; // '*', a JSONPath ('$...') or a header name
  end;

function MatchRequestReference(AFile: THttpFile; const AInner: string;
  out ARef: TRequestReference; out AMessage: string): TReferenceMatch;

{ True when AText contains at least one valid reference (resolved or not) }
function HasRequestReference(AFile: THttpFile; const AText: string): Boolean;

implementation

function BodySelectorProblem(const ASelector: string): string;
begin
  Result := '';
  if (ASelector = '*') or (ASelector[1] = '$') then
    Exit;
  if (ASelector[1] = '/') or (ASelector[1] = '(') then
    Result := 'XPath is not supported yet'
  else
    Result := 'Body selector must be * or a JSONPath starting with $';
end;

function MatchRequestReference(AFile: THttpFile; const AInner: string;
  out ARef: TRequestReference; out AMessage: string): TReferenceMatch;
var
  P, Q: Integer;
  Lower, Name, Rest, PartName: string;
  Found: Boolean;
begin
  Result := rmNotAReference;
  AMessage := '';
  ARef.RequestName := '';
  ARef.Scope := rsRequest;
  ARef.Part := rpBody;
  ARef.Selector := '';
  if (AFile = nil) or (AInner = '') then
    Exit;

  Lower := LowerCase(AInner);
  Found := False;
  Name := '';
  P := Pos('.', AInner);
  while P > 0 do
  begin
    if (Copy(Lower, P + 1, 8) = 'request.') or (Copy(Lower, P + 1, 9) = 'response.') then
    begin
      Name := Copy(AInner, 1, P - 1);
      if (Name <> '') and (AFile.FindEndpoint(Name) <> nil) then
      begin
        Found := True;
        Break;
      end;
    end;
    P := PosEx('.', AInner, P + 1);
  end;
  if not Found then
    Exit;

  ARef.RequestName := Name;
  if Copy(Lower, P + 1, 8) = 'request.' then
  begin
    ARef.Scope := rsRequest;
    Rest := Copy(AInner, P + 9, MaxInt);
  end
  else
  begin
    ARef.Scope := rsResponse;
    Rest := Copy(AInner, P + 10, MaxInt);
  end;

  Q := Pos('.', Rest);
  if Q = 0 then
    PartName := LowerCase(Rest)
  else
    PartName := LowerCase(Copy(Rest, 1, Q - 1));
  if PartName = 'body' then
    ARef.Part := rpBody
  else if PartName = 'headers' then
    ARef.Part := rpHeaders
  else
  begin
    Result := rmInvalid;
    AMessage := Format('Unknown part "%s" in reference to "%s" (expected body or headers)',
      [PartName, Name]);
    Exit;
  end;

  if Q > 0 then
    ARef.Selector := Trim(Copy(Rest, Q + 1, MaxInt));
  if ARef.Selector = '' then
  begin
    Result := rmInvalid;
    AMessage := Format('Missing selector in reference to "%s" (header name, * or JSONPath)', [Name]);
    Exit;
  end;
  if ARef.Part = rpBody then
  begin
    AMessage := BodySelectorProblem(ARef.Selector);
    if AMessage <> '' then
    begin
      Result := rmInvalid;
      Exit;
    end;
  end;
  Result := rmValid;
end;

function HasRequestReference(AFile: THttpFile; const AText: string): Boolean;
var
  I, CloseAt: Integer;
  Inner, Msg: string;
  Ref: TRequestReference;
begin
  Result := False;
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '{') and (I < Length(AText)) and (AText[I + 1] = '{') then
    begin
      CloseAt := PosEx('}}', AText, I + 2);
      if CloseAt = 0 then
        Exit;
      Inner := Trim(Copy(AText, I + 2, CloseAt - I - 2));
      if (Inner <> '') and (Inner[1] <> '$') and
         (MatchRequestReference(AFile, Inner, Ref, Msg) = rmValid) then
      begin
        Result := True;
        Exit;
      end;
      I := CloseAt + 2;
    end
    else
      Inc(I);
  end;
end;

end.
