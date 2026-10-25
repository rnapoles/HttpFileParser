(* HttpFileScripting - object instances available to double-brace expressions.

    Parser.Scripting.RegisterObject('app', MyConfig);
    ...  {{app.BaseUrl}}   {{app.Server.Port}}

  Properties are read through RTTI (unit TypInfo), so no wrapper code is
  needed: register the instance and every PUBLISHED property becomes readable.
  Delphi: derive from TPersistent or compile the class with the M+ switch.
  Names are case-insensitive. Supported property types: integers, Int64,
  floats (invariant "." separator), enumerations (their name), booleans,
  chars, strings. Properties holding objects can be walked through
  (app.Server.Port). Registered instances are NOT owned by the registry. *)
unit HttpFileScripting;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, TypInfo;

type
  EScriptError = class(Exception);

  TScriptObjectRegistry = class
  private
    FObjects: TStringList; // name -> instance (not owned)
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterObject(const AName: string; AInstance: TObject);
    procedure UnregisterObject(const AName: string);
    function IsRegistered(const AName: string): Boolean;
    function FindObject(const AName: string): TObject;
    procedure Clear;
    { APath = name.Property[.Property...]. Returns False when the first segment
      is not a registered object; raises EScriptError for bad property paths. }
    function TryEvaluate(const APath: string; out AValue: string): Boolean;
  end;

implementation

function PropKind(APropInfo: PPropInfo): TTypeKind;
begin
  {$IFDEF FPC}
  Result := APropInfo^.PropType^.Kind;
  {$ELSE}
  Result := APropInfo^.PropType^^.Kind;
  {$ENDIF}
end;

function PropTypeInfo(APropInfo: PPropInfo): PTypeInfo;
begin
  {$IFDEF FPC}
  Result := APropInfo^.PropType;
  {$ELSE}
  Result := APropInfo^.PropType^;
  {$ENDIF}
end;

function InvariantSettings: TFormatSettings;
begin
  {$IFDEF FPC}
  Result := DefaultFormatSettings;
  {$ELSE}
  Result := TFormatSettings.Create;
  {$ENDIF}
  Result.DecimalSeparator := '.';
end;

function SplitDots(const APath: string): TStringList;
var
  Start, I: Integer;
begin
  Result := TStringList.Create;
  Start := 1;
  for I := 1 to Length(APath) + 1 do
    if (I > Length(APath)) or (APath[I] = '.') then
    begin
      Result.Add(Copy(APath, Start, I - Start));
      Start := I + 1;
    end;
end;

function FormatProperty(AObject: TObject; APropInfo: PPropInfo; const APropName: string): string;
begin
  case PropKind(APropInfo) of
    tkInteger: Result := IntToStr(GetOrdProp(AObject, APropInfo));
    tkChar: Result := Chr(GetOrdProp(AObject, APropInfo));
    tkEnumeration: Result := GetEnumName(PropTypeInfo(APropInfo), GetOrdProp(AObject, APropInfo));
    tkInt64: Result := IntToStr(GetInt64Prop(AObject, APropInfo));
    tkFloat: Result := FloatToStr(GetFloatProp(AObject, APropInfo), InvariantSettings);
    {$IFDEF FPC}
    tkSString, tkLString, tkAString: Result := GetStrProp(AObject, APropInfo);
    tkWString: Result := GetWideStrProp(AObject, APropInfo);
    tkUString: Result := GetUnicodeStrProp(AObject, APropInfo);
    tkBool:
      if GetOrdProp(AObject, APropInfo) <> 0 then
        Result := 'True'
      else
        Result := 'False';
    {$ELSE}
    tkString, tkLString, tkWString, tkUString: Result := GetStrProp(AObject, APropInfo);
    {$ENDIF}
    tkClass:
      raise EScriptError.CreateFmt('Property "%s" is an object, read one of its properties', [APropName]);
  else
    raise EScriptError.CreateFmt('Property "%s" has an unsupported type (%s)',
      [APropName, GetEnumName(TypeInfo(TTypeKind), Ord(PropKind(APropInfo)))]);
  end;
end;

{ TScriptObjectRegistry }

constructor TScriptObjectRegistry.Create;
begin
  inherited Create;
  FObjects := TStringList.Create;
  FObjects.CaseSensitive := False;
end;

destructor TScriptObjectRegistry.Destroy;
begin
  FObjects.Free;
  inherited Destroy;
end;

procedure TScriptObjectRegistry.RegisterObject(const AName: string; AInstance: TObject);
var
  Idx: Integer;
begin
  if (AName = '') or (Pos('.', AName) > 0) then
    raise EScriptError.CreateFmt('Invalid object name "%s"', [AName]);
  if AInstance = nil then
    raise EScriptError.CreateFmt('Cannot register nil as "%s"', [AName]);
  Idx := FObjects.IndexOf(AName);
  if Idx >= 0 then
    FObjects.Objects[Idx] := AInstance
  else
    FObjects.AddObject(AName, AInstance);
end;

procedure TScriptObjectRegistry.UnregisterObject(const AName: string);
var
  Idx: Integer;
begin
  Idx := FObjects.IndexOf(AName);
  if Idx >= 0 then
    FObjects.Delete(Idx);
end;

function TScriptObjectRegistry.IsRegistered(const AName: string): Boolean;
begin
  Result := FObjects.IndexOf(AName) >= 0;
end;

function TScriptObjectRegistry.FindObject(const AName: string): TObject;
var
  Idx: Integer;
begin
  Idx := FObjects.IndexOf(AName);
  if Idx >= 0 then
    Result := FObjects.Objects[Idx]
  else
    Result := nil;
end;

procedure TScriptObjectRegistry.Clear;
begin
  FObjects.Clear;
end;

function TScriptObjectRegistry.TryEvaluate(const APath: string; out AValue: string): Boolean;
var
  Parts: TStringList;
  Current: TObject;
  PropInfo: PPropInfo;
  I: Integer;
begin
  AValue := '';
  Parts := SplitDots(APath);
  try
    Current := FindObject(Parts[0]);
    Result := Current <> nil;
    if not Result then
      Exit;
    if Parts.Count = 1 then
      raise EScriptError.CreateFmt('"%s" is an object, read one of its properties ("%s.<Property>")',
        [Parts[0], Parts[0]]);
    for I := 1 to Parts.Count - 1 do
    begin
      PropInfo := GetPropInfo(Current, Parts[I]);
      if PropInfo = nil then
        raise EScriptError.CreateFmt('"%s" has no published property "%s"', [Parts[I - 1], Parts[I]]);
      if I < Parts.Count - 1 then
      begin
        if PropKind(PropInfo) <> tkClass then
          raise EScriptError.CreateFmt('Property "%s" is not an object, cannot read "%s" from it',
            [Parts[I], Parts[I + 1]]);
        Current := GetObjectProp(Current, PropInfo);
        if Current = nil then
          raise EScriptError.CreateFmt('Property "%s" is nil', [Parts[I]]);
      end
      else
        AValue := FormatProperty(Current, PropInfo, Parts[I]);
    end;
  finally
    Parts.Free;
  end;
end;

end.
