# HttpFileParser

Zero-dependency parser for `.http` / `.rest` files. Delphi 12+ and Free Pascal 3.2.2+.

| Unit | Responsibility |
|---|---|
| `HttpFileLexer` | `FInput/FPos/FLen` lexer: `PeekChar`, `ConsumeChar`, `MatchToken`, line classification (`NextToken`) |
| `HttpFileAST` | `THttpFile`, `TVariable`, `TEndpoint`, headers, `THttpParseErrorList`, `EHttpFileParseException` |
| `HttpFileParser` | recursive descent parser, one `ParseXxx` per grammar rule (EBNF in the unit header) |
| `HttpFileInterpolator` | `{{variable}}` / `{{$function}}` expansion, cycle detection |
| `HttpFileFunctions` | function registry + `$guid $dotenv $randomInt $timestamp $datetime $localDatetime` |
| `HttpFileReferences` | syntax of `requestName.(request\|response).(body\|headers).(* \| JSONPath \| Header Name)` |
| `HttpFileResponses` | store of executed responses by request name |
| `HttpFileResponseParser` | raw HTTP response parser (`THttpResponseParser`) and saved-responses loader (`THttpResponseFileLoader`) |
| `HttpFileExecutor` | `IRequestExecutor` + abstract `TRequestExecutor` (check, build message, `DoSend`, store, re-parse); one subclass per transport |
| `HttpFileResponseBuilder` | transport neutral collector: header lines + body chunks -> `THttpResponse` |
| `CurlRequestExecutor` | `TCurlRequestExecutor` (libcurl through `src/libpascurl/libpascurl.pas`, GPL-3.0); needs libcurl at run time |
| `HttpFileSelectors` | value extraction from bodies (`*` and JSONPath through `TJSONPath`; XPath not supported yet) |
| `HttpFileScripting` | RTTI registry of object instances readable from expressions |
| `jsonpath/` | the JSONPath units (`src/jsonpath`, add to the unit search path) |
| `HttpFileDateFormat` | RFC 1123, ISO 8601, Day.js style formats |

```pascal
P := THttpFileParser.CreateFromFile('api.http');   // or Create(TextString)
P.Functions.RegisterFunction('upper', Upper, 1, 1); // {{$upper 'x'}}
for E in P.HttpFile.Endpoints ... ; P.Errors[I].Row / .Column / .Message
```

Build & run tests:

    sh build/build_fpc.sh        (or build\build_fpc.bat / build\build_delphi.bat)

Dump an `.http` file (sample program):

    sh build/build_dump_fpc.sh && build/out/DumpHttpFile examples/sample.http

## Converters

| Unit | Responsibility |
|---|---|
| `CodeGenerator` | `TCodeGenerator` base (template method `Generate` -> `DoGenerate`), warnings, generator registry, `SaveGeneratedFiles` |
| `CurlGenerator` | `TCurlGenerator` (`curl`, `.sh` by default; `Target := ctWindowsBatch` or id `curl-bat` for `.bat`; `ExportVariables`) via pluggable `TCurlDialect` |
| `PostmanCollectionGenerator` | `TPostmanCollectionGenerator` (`postman`): collection v2.1 + environment |
| `JsonWriter` | dependency-free JSON writer used by the Postman generator |

Add a new target: derive from `TCodeGenerator`, override `Id`, `Description`, `DoGenerate`, and call `RegisterCodeGenerator` in `initialization`.

    sh build/build_convert_fpc.sh && build/out/ConvertHttpFile examples/sample.http curl out

## Request references and scripting objects

    @authToken = {{login.response.headers.X-AuthToken}}   (header name is case-insensitive)
    @commentId = {{createComment.response.body.$.id}}      (JSONPath, or * for the whole body)
    GET {{api.request.body.$.id}}                          (request scope reads the file itself)

The parser does not run requests. Without a stored response the text stays as written. After running
a request: `Parser.Responses.Put('login')` (set `Body`, `AddHeader`), then `Parser.Parse` again.

    Parser.Scripting.RegisterObject('app', MyConfig);   // {{app.BaseUrl}}  {{app.Server.Port}}

Published properties are read through RTTI (Delphi: derive from `TPersistent` or use `{$M+}`).

Feature tour: `examples/features.http` (run `DumpHttpFile examples/features.http --demo`).

## Diagnostics

`Parser.Errors` holds errors, warnings and info entries (`Severity`, start `Row/Column`, exclusive end
`EndRow/EndColumn`, `Rule`). Use `ErrorCount`, `WarningCount`, `HasErrors`; `Count` is the total.
Warnings: unresolved placeholders (`Placeholder`), skipped scripts (`Script`), `@name` without a name.

## Executing requests

Derive from `TRequestExecutor`, override `DoSend(const ARequest: THttpRequestMessage): THttpResponse`
and call `Execute('login')`, `ExecuteAt(i)` or `ExecuteAll` through `IRequestExecutor`.
Each response is stored in `Parser.Responses`, the file is parsed again, and later requests resolve
`login.response...`. Saved responses (`### name` / `# @name`, status line, headers, blank line, body)
load with `THttpResponseFileLoader.LoadFromFile(file, Parser.Responses)`.

Run a file against real servers: `sh build/build_run_fpc.sh && build/out/RunHttpFile examples/features.http`
(`TCurlRequestExecutor.Create(Parser)`; options `FollowRedirects`, `TimeoutSeconds`, `VerifyTls`, `UserAgent`).
Note: `libpascurl.pas` is GPL-3.0; linking it makes the resulting program subject to that license.
