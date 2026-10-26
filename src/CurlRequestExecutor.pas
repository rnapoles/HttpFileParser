(* CurlRequestExecutor - TRequestExecutor on top of libcurl (unit libcurl,
  src/libcurl/libcurl.pas).

  Needs libcurl at run time (libcurl.dll / libcurl.so / libcurl.dylib) and
  the libcurl unit on the unit search path.

  Mapping of a THttpRequestMessage:
    method   GET: default, HEAD: NOBODY, others: CUSTOMREQUEST
    body     POSTFIELDS (bytes of the text or of the "< file"); a POST/PUT/PATCH
             without body sends Content-Length: 0
    headers  one "Name: value" per header; an empty value sends "Name;"
             (without a Content-Type header none is sent, curl would invent
             application/x-www-form-urlencoded; "Expect:" is suppressed)
    version  HTTP/1.0, HTTP/1.1, HTTP/2, HTTP/3
  Responses are decoded (gzip, deflate, br when libcurl supports them). *)
unit CurlRequestExecutor;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}{$X+}

interface

uses
  SysUtils, libcurl, HttpFileResponses, HttpFileResponseParser,
  HttpFileResponseBuilder, HttpFileParser, HttpFileExecutor;

type
  TCurlRequestExecutor = class(TRequestExecutor)
  private
    FFollowRedirects: Boolean;
    FTimeoutSeconds: Integer;
    FConnectTimeoutSeconds: Integer;
    FVerifyTls: Boolean;
    FUserAgent: string;
  protected
    function DoSend(const ARequest: THttpRequestMessage): THttpResponse; override;
  public
    constructor Create(AParser: THttpFileParser);
    { follow 3xx responses (default True) }
    property FollowRedirects: Boolean read FFollowRedirects write FFollowRedirects;
    { whole transfer, 0 = no limit (default 60) }
    property TimeoutSeconds: Integer read FTimeoutSeconds write FTimeoutSeconds;
    property ConnectTimeoutSeconds: Integer read FConnectTimeoutSeconds write FConnectTimeoutSeconds;
    { check certificate and host name (default True) }
    property VerifyTls: Boolean read FVerifyTls write FVerifyTls;
    property UserAgent: string read FUserAgent write FUserAgent;
  end;

implementation

type
  TCurlLong = {$IFDEF FPC}PtrInt{$ELSE}NativeInt{$ENDIF}; // C "long" in varargs
  TSizeT = {$IFDEF FPC}PtrUInt{$ELSE}NativeUInt{$ENDIF};

const
  EmptyCString: AnsiChar = #0;

var
  GCurlReady: Boolean = False;

procedure EnsureCurlGlobalInit;
begin
  if GCurlReady then
    Exit;
  if curl_global_init(CURL_GLOBAL_DEFAULT) <> CURLE_OK then
    raise ERequestExecutor.Create('libcurl could not be initialised');
  GCurlReady := True;
end;

function WriteCallback(Buffer: Pointer; Size, Count: TSizeT; UserData: Pointer): TSizeT; cdecl;
begin
  Result := Size * Count;
  THttpResponseBuilder(UserData).AddBodyData(Buffer, Integer(Result));
end;

function HeaderCallback(Buffer: Pointer; Size, Count: TSizeT; UserData: Pointer): TSizeT; cdecl;
begin
  Result := Size * Count;
  THttpResponseBuilder(UserData).AddHeaderData(Buffer, Integer(Result));
end;

function CStringToText(AText: PUTF8Char): string;
var
  Bytes: RawByteString;
begin
  if AText = nil then
    Result := ''
  else
  begin
    Bytes := PAnsiChar(Pointer(AText));
    Result := BytesToText(Bytes);
  end;
end;

{ RAII wrapper around one easy handle }
type
  TCurlEasy = class
  private
    FHandle: PCURL;
    FHeaderList: Pcurl_slist;
    FErrorBuffer: array[0..CURL_ERROR_SIZE] of AnsiChar;
    procedure Check(ACode: CURLcode);
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetLong(AOption: CURLoption; AValue: TCurlLong);
    procedure SetPointer(AOption: CURLoption; AValue: Pointer);
    procedure SetText(AOption: CURLoption; const AValue: RawByteString);
    procedure AddHeader(const ALine: RawByteString);
    procedure Perform(const AUrl: string);
  end;

constructor TCurlEasy.Create;
begin
  inherited Create;
  FHandle := curl_easy_init;
  if FHandle = nil then
    raise ERequestExecutor.Create('curl_easy_init failed');
  FErrorBuffer[0] := #0;
end;

destructor TCurlEasy.Destroy;
begin
  if FHeaderList <> nil then
    curl_slist_free_all(FHeaderList);
  if FHandle <> nil then
    curl_easy_cleanup(FHandle);
  inherited Destroy;
end;

procedure TCurlEasy.Check(ACode: CURLcode);
begin
  if ACode <> CURLE_OK then
    raise ERequestExecutor.CreateFmt('libcurl: %s', [CStringToText(curl_easy_strerror(ACode))]);
end;

procedure TCurlEasy.SetLong(AOption: CURLoption; AValue: TCurlLong);
begin
  Check(curl_easy_setopt(FHandle, AOption, AValue));
end;

procedure TCurlEasy.SetPointer(AOption: CURLoption; AValue: Pointer);
begin
  Check(curl_easy_setopt(FHandle, AOption, AValue));
end;

procedure TCurlEasy.SetText(AOption: CURLoption; const AValue: RawByteString);
var
  Text: Pointer;
begin
  Text := Pointer(AValue);
  if Text = nil then
    Text := @EmptyCString; // an empty string, not NULL (NULL resets the option)
  Check(curl_easy_setopt(FHandle, AOption, Text)); // libcurl copies the text
end;

procedure TCurlEasy.AddHeader(const ALine: RawByteString);
begin
  FHeaderList := curl_slist_append(FHeaderList, PUTF8Char(Pointer(ALine)));
  if FHeaderList = nil then
    raise ERequestExecutor.Create('libcurl: out of memory while adding a header');
end;

procedure TCurlEasy.Perform(const AUrl: string);
var
  Code: CURLcode;
  Detail: string;
begin
  if FHeaderList <> nil then
    SetPointer(CURLOPT_HTTPHEADER, FHeaderList);
  SetPointer(CURLOPT_ERRORBUFFER, @FErrorBuffer[0]);
  Code := curl_easy_perform(FHandle);
  if Code <> CURLE_OK then
  begin
    Detail := CStringToText(curl_easy_strerror(Code));
    if FErrorBuffer[0] <> #0 then
      Detail := Detail + ' - ' + CStringToText(PUTF8Char(@FErrorBuffer[0]));
    raise ERequestExecutor.CreateFmt('Request to %s failed: %s', [AUrl, Detail]);
  end;
end;

{ configuration steps, one per concern }

procedure ConfigureMethod(AEasy: TCurlEasy; const AMethod: string; AHasBody: Boolean);
begin
  if AMethod = 'HEAD' then
    AEasy.SetLong(CURLOPT_NOBODY, 1)
  else if (AMethod <> 'GET') or AHasBody then
    AEasy.SetText(CURLOPT_CUSTOMREQUEST, TextToBytes(AMethod));
end;

procedure ConfigureVersion(AEasy: TCurlEasy; const AVersion: string);
var
  Version: string;
begin
  Version := UpperCase(AVersion);
  if Version = 'HTTP/1.0' then
    AEasy.SetLong(CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_0)
  else if Version = 'HTTP/1.1' then
    AEasy.SetLong(CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1)
  else if (Version = 'HTTP/2') or (Version = 'HTTP/2.0') then
    AEasy.SetLong(CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0)
  else if (Version = 'HTTP/3') or (Version = 'HTTP/3.0') then
    AEasy.SetLong(CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_3);
end;

procedure ConfigureHeaders(AEasy: TCurlEasy; const ARequest: THttpRequestMessage;
  AHasBody: Boolean);
var
  I: Integer;
  HasContentType, HasExpect: Boolean;
begin
  HasContentType := False;
  HasExpect := False;
  for I := 0 to High(ARequest.Headers) do
  begin
    if SameText(ARequest.Headers[I].Name, 'Content-Type') then
      HasContentType := True;
    if SameText(ARequest.Headers[I].Name, 'Expect') then
      HasExpect := True;
    if ARequest.Headers[I].Value = '' then
      AEasy.AddHeader(TextToBytes(ARequest.Headers[I].Name + ';')) // send the header empty
    else
      AEasy.AddHeader(TextToBytes(ARequest.Headers[I].Name + ': ' + ARequest.Headers[I].Value));
  end;
  if AHasBody and not HasContentType then
    AEasy.AddHeader('Content-Type:'); // do not let curl invent one
  if not HasExpect then
    AEasy.AddHeader('Expect:');
end;

procedure ConfigureBody(AEasy: TCurlEasy; const AMethod: string; const ABody: RawByteString);
begin
  if ABody <> '' then
  begin
    AEasy.SetLong(CURLOPT_POSTFIELDSIZE, Length(ABody));
    AEasy.SetPointer(CURLOPT_POSTFIELDS, Pointer(ABody)); // not copied: ABody must outlive Perform
  end
  else if (AMethod = 'POST') or (AMethod = 'PUT') or (AMethod = 'PATCH') then
  begin
    AEasy.SetLong(CURLOPT_POSTFIELDSIZE, 0);
    AEasy.SetPointer(CURLOPT_POSTFIELDS, @EmptyCString);
  end;
end;

{ TCurlRequestExecutor }

constructor TCurlRequestExecutor.Create(AParser: THttpFileParser);
begin
  inherited Create(AParser);
  FFollowRedirects := True;
  FTimeoutSeconds := 60;
  FConnectTimeoutSeconds := 30;
  FVerifyTls := True;
  FUserAgent := 'HttpFileParser';
end;

function TCurlRequestExecutor.DoSend(const ARequest: THttpRequestMessage): THttpResponse;
var
  Easy: TCurlEasy;
  Builder: THttpResponseBuilder;
  Body: RawByteString;
begin
  EnsureCurlGlobalInit;
  Body := ReadBodyBytes(ARequest);
  Builder := THttpResponseBuilder.Create;
  try
    Easy := TCurlEasy.Create;
    try
      Easy.SetText(CURLOPT_URL, TextToBytes(ARequest.Url));
      ConfigureMethod(Easy, ARequest.Method, Body <> '');
      ConfigureVersion(Easy, ARequest.HttpVersion);
      ConfigureHeaders(Easy, ARequest, Body <> '');
      ConfigureBody(Easy, ARequest.Method, Body);

      Easy.SetLong(CURLOPT_NOSIGNAL, 1);
      Easy.SetLong(CURLOPT_FOLLOWLOCATION, Ord(FFollowRedirects));
      if FTimeoutSeconds > 0 then
        Easy.SetLong(CURLOPT_TIMEOUT, FTimeoutSeconds);
      if FConnectTimeoutSeconds > 0 then
        Easy.SetLong(CURLOPT_CONNECTTIMEOUT, FConnectTimeoutSeconds);
      if not FVerifyTls then
      begin
        Easy.SetLong(CURLOPT_SSL_VERIFYPEER, 0);
        Easy.SetLong(CURLOPT_SSL_VERIFYHOST, 0);
      end;
      if FUserAgent <> '' then
        Easy.SetText(CURLOPT_USERAGENT, TextToBytes(FUserAgent));
      Easy.SetText(CURLOPT_ACCEPT_ENCODING, ''); // all encodings libcurl supports

      Easy.SetPointer(CURLOPT_WRITEFUNCTION, @WriteCallback);
      Easy.SetPointer(CURLOPT_WRITEDATA, Builder);
      Easy.SetPointer(CURLOPT_HEADERFUNCTION, @HeaderCallback);
      Easy.SetPointer(CURLOPT_HEADERDATA, Builder);
      Easy.Perform(ARequest.Url);
    finally
      Easy.Free;
    end;
    try
      Result := Builder.Build;
    except
      on E: EHttpResponseError do
        raise ERequestExecutor.CreateFmt('Invalid response from %s: %s', [ARequest.Url, E.Message]);
    end;
  finally
    Builder.Free;
  end;
end;

initialization

finalization
  if GCurlReady then
    curl_global_cleanup;

end.
