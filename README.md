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
| `CurlRequestExecutor` | `TCurlRequestExecutor` (libcurl through the `libcurl` unit in `src/libcurl/`); needs libcurl at run time |
| `HttpFileLinter` | `THttpFileLinter` + rule classes (`THttpLintRule`): duplicate request names, unused variables, unresolved placeholders, circular references; warnings with positions |
| `HttpFilePrinter` | `THttpFilePrinter`: canonical, stable .http text from a `THttpFile` (raw or resolved values, CRLF, alignment) |
| `HttpFileSelectors` | value extraction from bodies (`*` and JSONPath through `TJSONPath`; XPath not supported yet) |
| `HttpFileScripting` | RTTI registry of object instances readable from expressions |
| `jsonpath/` | the JSONPath units (`src/jsonpath`, add to the unit search path) |
| `HttpFileDateFormat` | RFC 1123, ISO 8601, Day.js style formats |

```pascal
P := THttpFileParser.CreateFromFile('api.http');   // or Create(TextString)
P.Functions.RegisterFunction('upper', Upper, 1, 1); // {{$upper 'x'}}
for E in P.HttpFile.Endpoints ... ; P.Errors[I].Row / .Column / .Message
```

## Build, test, run the samples

| Windows | Linux / macOS (Free Pascal only) |
|---|---|
| `build.bat [fpc\|delphi\|all] [win32\|win64]` | `./build.sh` |
| `test.bat [fpc\|delphi\|all] [win32\|win64]` | `./test.sh` |
| `run-samples.bat [fpc\|delphi\|all] [win32\|win64]` | `./run-samples.sh` |

Defaults on Windows: `all`, `win64`. `test` and `run-samples` build first. Output:
`build\fpc-<platform>\bin` and `build\delphi-<platform>\bin` (units in `obj`, sample output in `samples`),
on Linux `build/fpc-linux64/bin` (the platform is the native one).

- Delphi: set `RSVARS` to the full path of `rsvars.bat`; it sets `BDS`, which the scripts use to find `dcc32.exe` / `dcc64.exe`.
- FPC: `fpc` on the `PATH` (`win32` needs the i386 compiler, `win64` the x86_64 one).
- `RunHttpFile` needs libcurl (`libcurl.dll` on the `PATH` or in the `bin` folder) and python for the local test server;
  `run-samples.bat` skips that step when one is missing.

## Converters

| Unit | Responsibility |
|---|---|
| `CodeGenerator` | `TCodeGenerator` base (template method `Generate` -> `DoGenerate`), warnings, generator registry, `SaveGeneratedFiles` |
| `CurlGenerator` | `TCurlGenerator` (`curl`, `.sh` by default; `Target := ctWindowsBatch` or id `curl-bat` for `.bat`; `ExportVariables`) via pluggable `TCurlDialect` |
| `PostmanCollectionGenerator` | `TPostmanCollectionGenerator` (`postman`): collection v2.1 + environment |
| `JsonWriter` | dependency-free JSON writer used by the Postman generator |

Add a new target: derive from `TCodeGenerator`, override `Id`, `Description`, `DoGenerate`, and call `RegisterCodeGenerator` in `initialization`.

    build\fpc-win64\bin\ConvertHttpFile examples\features.http curl out

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

Run a file against real servers: `RunHttpFile examples/jsonplaceholder.http` (built by the scripts above)
(`TCurlRequestExecutor.Create(Parser)`; options `FollowRedirects`, `TimeoutSeconds`, `VerifyTls`, `UserAgent`).

## Linux check with Docker

    docker compose up -d --build                         # idle container (sleep infinity, bash)
    docker compose exec dev bash build/check_linux.sh    # build.sh + test.sh + run-samples.sh
    docker compose exec dev bash                         # interactive shell
    docker compose down

On Linux/macOS hosts run `export HOST_UID=$(id -u) HOST_GID=$(id -g)` before `up --build` so the files
written to the mounted project belong to you.

## Lint and format

    LintHttpFile examples/features.http [--strict]    file:row:col: warning: message [rule]
    FormatHttpFile examples/features.http [--resolved] [--crlf] [--write]

`THttpFileLinter.Create(Parser.Functions, Parser.Scripting)` then `Lint(Parser.HttpFile, Diagnostics)`;
add your own check with `AddRule(TMyRule.Create)` (derive from `THttpLintRule`).
