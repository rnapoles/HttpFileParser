(* HttpFileInterpolator - expands {{variable}} and {{$function args}} expressions.

  Rules
  * {{name}}            replaced by the (recursively resolved) variable value;
                        unknown names are left untouched (request / environment
                        variables are resolved by the HTTP client, not here).
  * {{$fn arg ...}}     calls a registered function. Arguments are separated by
                        blanks; '...' and "..." group an argument with blanks.
                        Unknown functions / bad arguments leave the expression
                        untouched and add an entry to the error list.
  * In variable values {{$jsonpath ...}} and {{$xpath ...}} are kept raw.
  * Replacement is single pass: replaced text is never scanned again. *)
unit HttpFileInterpolator;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, StrUtils, HttpFileAST, HttpFileFunctions;

type
  THttpInterpolator = class
  private
    FFile: THttpFile;
    FFunctions: THttpFunctionRegistry;
    FContext: THttpFunctionContext;
    FErrors: THttpParseErrorList;
    FState: array of Byte; // 0 = pending, 1 = resolving, 2 = done
    function FindVariableIndex(const AName: string): Integer;
    function ResolveVariable(AIndex: Integer): string;
    function EvaluateFunction(const AInner, ARaw: string; ARow, ACol: Integer;
      APreserveDeferred: Boolean): string;
    procedure ParseCall(const AInner: string; out AName: string; out AArgs: THttpArgs);
    procedure Report(const AText: string; AIndex, ARow, ACol: Integer;
      const AMessage, AToken, ARule: string);
  public
    constructor Create(AFile: THttpFile; AFunctions: THttpFunctionRegistry;
      AContext: THttpFunctionContext; AErrors: THttpParseErrorList);
    { ARow/ACol are the coordinates of the first character of AText. }
    function Expand(const AText: string; ARow, ACol: Integer;
      APreserveDeferred: Boolean): string;
    { Resolves every variable, then every endpoint. }
    procedure Apply;
  end;

implementation

function IsWs(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

constructor THttpInterpolator.Create(AFile: THttpFile; AFunctions: THttpFunctionRegistry;
  AContext: THttpFunctionContext; AErrors: THttpParseErrorList);
begin
  inherited Create;
  FFile := AFile;
  FFunctions := AFunctions;
  FContext := AContext;
  FErrors := AErrors;
end;

procedure THttpInterpolator.Report(const AText: string; AIndex, ARow, ACol: Integer;
  const AMessage, AToken, ARule: string);
var
  K, R, C: Integer;
begin
  R := ARow;
  C := ACol;
  for K := 1 to AIndex - 1 do
    if AText[K] = #10 then
    begin
      Inc(R);
      C := 1;
    end
    else
      Inc(C);
  FErrors.Add(R, C, AMessage, AToken, ARule);
end;

function THttpInterpolator.FindVariableIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := High(FFile.Variables) downto 0 do
    if FFile.Variables[I].Name = AName then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function THttpInterpolator.ResolveVariable(AIndex: Integer): string;
var
  V: TVariable;
begin
  V := FFile.Variables[AIndex];
  case FState[AIndex] of
    2: Result := V.Value;
    1:
      begin
        FErrors.Add(V.Row, V.Column, 'Circular variable reference: ' + V.Name,
          '{{' + V.Name + '}}', 'VariableReference');
        Result := '{{' + V.Name + '}}';
      end;
  else
    begin
      FState[AIndex] := 1;
      V.Value := Expand(V.RawValue, V.Row, V.ValueColumn, True);
      FState[AIndex] := 2;
      Result := V.Value;
    end;
  end;
end;

procedure THttpInterpolator.ParseCall(const AInner: string; out AName: string;
  out AArgs: THttpArgs);
var
  I, L, Start: Integer;
  Q: Char;
begin
  L := Length(AInner);
  I := 2; // skip '$'
  Start := I;
  while (I <= L) and not IsWs(AInner[I]) do
    Inc(I);
  AName := Copy(AInner, Start, I - Start);
  SetLength(AArgs, 0);
  while True do
  begin
    while (I <= L) and IsWs(AInner[I]) do
      Inc(I);
    if I > L then
      Break;
    if (AInner[I] = '"') or (AInner[I] = '''') then
    begin
      Q := AInner[I];
      Inc(I);
      Start := I;
      while (I <= L) and (AInner[I] <> Q) do
        Inc(I);
      if I > L then
        raise EHttpFunctionError.Create('Unterminated quoted argument');
      SetLength(AArgs, Length(AArgs) + 1);
      AArgs[High(AArgs)] := Copy(AInner, Start, I - Start);
      Inc(I);
    end
    else
    begin
      Start := I;
      while (I <= L) and not IsWs(AInner[I]) do
        Inc(I);
      SetLength(AArgs, Length(AArgs) + 1);
      AArgs[High(AArgs)] := Copy(AInner, Start, I - Start);
    end;
  end;
end;

function THttpInterpolator.EvaluateFunction(const AInner, ARaw: string;
  ARow, ACol: Integer; APreserveDeferred: Boolean): string;
var
  Name: string;
  Args: THttpArgs;
begin
  try
    ParseCall(AInner, Name, Args);
    if APreserveDeferred and
       ((LowerCase(Name) = 'jsonpath') or (LowerCase(Name) = 'xpath')) then
      Result := ARaw
    else
      Result := FFunctions.Execute(Name, Args, FContext);
  except
    on E: Exception do
    begin
      FErrors.Add(ARow, ACol, E.Message, ARaw, 'FunctionCall');
      Result := ARaw;
    end;
  end;
end;

function THttpInterpolator.Expand(const AText: string; ARow, ACol: Integer;
  APreserveDeferred: Boolean): string;
var
  I, RunStart, CloseAt, Idx, R, C, K: Integer;
  Inner, Raw: string;
begin
  Result := '';
  I := 1;
  RunStart := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '{') and (I < Length(AText)) and (AText[I + 1] = '{') then
    begin
      Result := Result + Copy(AText, RunStart, I - RunStart);
      CloseAt := PosEx('}}', AText, I + 2);
      if CloseAt = 0 then
      begin
        Report(AText, I, ARow, ACol, 'Unterminated {{ expression', Copy(AText, I, 20),
          'Expression');
        Result := Result + Copy(AText, I, MaxInt);
        Exit;
      end;
      Raw := Copy(AText, I, CloseAt + 2 - I);
      Inner := Trim(Copy(AText, I + 2, CloseAt - I - 2));
      // coordinates of "{{"
      R := ARow;
      C := ACol;
      for K := 1 to I - 1 do
        if AText[K] = #10 then
        begin
          Inc(R);
          C := 1;
        end
        else
          Inc(C);
      if Inner = '' then
        Result := Result + Raw
      else if Inner[1] = '$' then
        Result := Result + EvaluateFunction(Inner, Raw, R, C, APreserveDeferred)
      else
      begin
        Idx := FindVariableIndex(Inner);
        if Idx >= 0 then
          Result := Result + ResolveVariable(Idx)
        else
          Result := Result + Raw;
      end;
      I := CloseAt + 2;
      RunStart := I;
    end
    else
      Inc(I);
  end;
  Result := Result + Copy(AText, RunStart, MaxInt);
end;

procedure THttpInterpolator.Apply;
var
  I, J: Integer;
  E: TEndpoint;
  H: TRequestHeader;
begin
  SetLength(FState, Length(FFile.Variables));
  for I := 0 to High(FState) do
    FState[I] := 0;
  for I := 0 to High(FState) do
    ResolveVariable(I);

  for I := 0 to High(FFile.Endpoints) do
  begin
    E := FFile.Endpoints[I];
    E.Url := Expand(E.RawUrl, E.Row, E.UrlColumn, False);
    for J := 0 to High(E.RequestHeaders) do
    begin
      H := E.RequestHeaders[J];
      H.Value := Expand(H.RawValue, H.Row, H.ValueColumn, False);
    end;
    if E.BodyFilePath <> '' then
      E.BodyFilePath := Expand(E.BodyFilePath, E.BodyRow, E.BodyFileColumn, False)
    else
      E.RequestBody := Expand(E.RawRequestBody, E.BodyRow, 1, False);
  end;
end;

end.
