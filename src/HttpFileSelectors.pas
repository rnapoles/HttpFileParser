(* HttpFileSelectors - extracts a value from a body.

  Selector kinds:   *        the whole body
                    $...     JSONPath (TJSONPath, RFC 9535)
  XPath is not supported yet; add it here (the only unit that knows how to
  read bodies) and in BodySelectorProblem of HttpFileReferences.

  JSONPath results: no match -> error; one match -> its text (strings without
  quotes, objects and arrays as compact JSON); several matches -> a compact
  JSON array. *)
unit HttpFileSelectors;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, JSONPathJSON, JSONPathLexer, JSONPathQuery;

type
  EHttpSelectorError = class(Exception);

function SelectFromBody(const ABody, ASelector: string): string;

implementation

function SelectJsonPath(const ABody, AQuery: string): string;
var
  Doc: TJSONValue;
  Path: TJSONPath;
  Res: TJSONPathResult;
begin
  Doc := nil;
  Path := nil;
  Res := nil;
  try
    try
      Doc := ParseJSON(ABody);
    except
      on E: EJSONPathJSONError do
        raise EHttpSelectorError.Create('Body is not valid JSON: ' + E.Message);
    end;
    try
      Path := TJSONPath.Create(AQuery);
    except
      on E: EJSONPathParseException do
        raise EHttpSelectorError.Create('Invalid JSONPath "' + AQuery + '": ' + E.Message);
    end;
    Res := Path.Evaluate(Doc);
    if Res.Count = 0 then
      raise EHttpSelectorError.Create('JSONPath "' + AQuery + '" matched nothing');
    if Res.Count = 1 then
      Result := Res.Values[0].AsString
    else
      Result := Res.ToJSONText;
  finally
    Res.Free;
    Path.Free;
    Doc.Free;
  end;
end;

function SelectFromBody(const ABody, ASelector: string): string;
begin
  if ASelector = '*' then
    Result := ABody
  else if (ASelector <> '') and (ASelector[1] = '$') then
    Result := SelectJsonPath(ABody, ASelector)
  else
    raise EHttpSelectorError.Create('Unsupported body selector "' + ASelector +
      '" (use * or a JSONPath starting with $)');
end;

end.
