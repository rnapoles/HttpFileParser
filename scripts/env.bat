@rem Shared by build.bat, test.bat and run-samples.bat.
@rem Call it WITHOUT setlocal so the variables reach the caller.
@rem   Input : %1 = fpc, delphi or all (default all)    %2 = win32 or win64 (default win64)
@rem   Output: ROOT COMPILER PLATFORM PROGRAMS    exit code 2 on bad arguments
@for %%I in ("%~dp0..") do @set "ROOT=%%~fI"
@set "COMPILER=%~1"
@if not defined COMPILER set "COMPILER=all"
@set "PLATFORM=%~2"
@if not defined PLATFORM set "PLATFORM=win64"

@set "OK="
@for %%C in (fpc delphi all) do @if /i "%COMPILER%"=="%%C" set "OK=1"
@if not defined OK goto :usage
@set "OK="
@for %%P in (win32 win64) do @if /i "%PLATFORM%"=="%%P" set "OK=1"
@if not defined OK goto :usage

@if /i "%PLATFORM%"=="win32" set "PLATFORM=win32"
@if /i "%PLATFORM%"=="win64" set "PLATFORM=win64"
@if /i "%COMPILER%"=="fpc" set "COMPILER=fpc"
@if /i "%COMPILER%"=="delphi" set "COMPILER=delphi"
@if /i "%COMPILER%"=="all" set "COMPILER=all"

@rem the test project and the example programs, without extension
@set "PROGRAMS=tests\HttpFileTests examples\DumpHttpFile examples\ConvertHttpFile examples\LintHttpFile examples\FormatHttpFile examples\RunHttpFile"
@exit /b 0

:usage
@echo Usage: build.bat / test.bat / run-samples.bat [fpc/delphi/all] [win32/win64]
@echo        defaults: all win64
@exit /b 2
