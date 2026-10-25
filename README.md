# HttpFileParser

Zero-dependency parser for `.http` / `.rest` files. Delphi 12+ and Free Pascal 3.2.2+.

| Unit | Responsibility |
|---|---|
| `HttpFileLexer` | `FInput/FPos/FLen` lexer: `PeekChar`, `ConsumeChar`, `MatchToken`, line classification (`NextToken`) |
| `HttpFileAST` | `THttpFile`, `TVariable`, `TEndpoint`, headers, `THttpParseErrorList`, `EHttpFileParseException` |
| `HttpFileParser` | recursive descent parser, one `ParseXxx` per grammar rule (EBNF in the unit header) |
| `HttpFileInterpolator` | `{{variable}}` / `{{$function}}` expansion, cycle detection |
| `HttpFileFunctions` | function registry + `$guid $dotenv $randomInt $timestamp $datetime $localDatetime $jsonpath $xpath` |
| `HttpFileDateFormat` | RFC 1123, ISO 8601, Day.js style formats |

```pascal
P := THttpFileParser.CreateFromFile('api.http');   // or Create(TextString)
P.Functions.RegisterFunction('upper', Upper, 1, 1); // {{$upper 'x'}}
for E in P.HttpFile.Endpoints ... ; P.Errors[I].Row / .Column / .Message
```

Build & run tests:

    sh build/build_fpc.sh        (or build\build_fpc.bat / build\build_delphi.bat)
