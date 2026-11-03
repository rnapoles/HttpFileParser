@echo off
rem Builds, then runs the example programs on the files in examples\ and checks their results.
rem   run-samples.bat [fpc/delphi/all] [win32/win64]  defaults: all win64
rem Output: build\TOOL-PLATFORM\samples
rem RunHttpFile needs python (a small local server) and libcurl.dll (PATH or the bin folder);
rem that step is skipped with a message when one of them is missing.
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0scripts\env.bat" %*
if errorlevel 1 exit /b 2
cd /d "%ROOT%"

call "%ROOT%\build.bat" %COMPILER% %PLATFORM%
if errorlevel 1 exit /b 1

set "FAILED=0"
if /i "%COMPILER%"=="fpc" call :samples fpc
if /i "%COMPILER%"=="delphi" call :samples delphi
if /i "%COMPILER%"=="all" (
  call :samples fpc
  call :samples delphi
)
if "%FAILED%"=="0" (echo ALL SAMPLES PASSED) else (echo SAMPLES FAILED)
exit /b %FAILED%

:samples
set "BIN=%ROOT%\build\%~1-%PLATFORM%\bin"
set "OUT=%ROOT%\build\%~1-%PLATFORM%\samples"
if not exist "%OUT%" mkdir "%OUT%"
echo ==== samples: %~1 %PLATFORM%

echo -- DumpHttpFile, features.http with the demo host
"%BIN%\DumpHttpFile.exe" examples\features.http --demo > "%OUT%\dump.txt"
if errorlevel 1 (echo FAILED: DumpHttpFile & set "FAILED=1")
findstr /c:"Bearer at-456" "%OUT%\dump.txt" >nul
if errorlevel 1 (echo FAILED: the response references were not resolved & set "FAILED=1")

echo -- ConvertHttpFile, curl and curl-bat and postman
for %%F in (curl curl-bat postman) do (
  "%BIN%\ConvertHttpFile.exe" examples\features.http %%F "%OUT%\generated" >nul
  if errorlevel 1 (echo FAILED: ConvertHttpFile %%F & set "FAILED=1")
)
for %%F in (features.sh features.bat features.postman_collection.json features.postman_environment.json) do (
  if not exist "%OUT%\generated\%%F" (echo FAILED: %%F was not generated & set "FAILED=1")
)

echo -- LintHttpFile
"%BIN%\LintHttpFile.exe" examples\local.http
if errorlevel 1 (echo FAILED: LintHttpFile local.http & set "FAILED=1")
"%BIN%\LintHttpFile.exe" examples\features.http > "%OUT%\lint.txt"
if errorlevel 1 (echo FAILED: LintHttpFile features.http & set "FAILED=1")
findstr /c:"lint-unresolved-placeholder" "%OUT%\lint.txt" >nul
if errorlevel 1 (echo FAILED: the linter did not report the placeholders & set "FAILED=1")

echo -- FormatHttpFile, formatting twice must not change the text
"%BIN%\FormatHttpFile.exe" examples\features.http > "%OUT%\formatted1.http"
if errorlevel 1 (echo FAILED: FormatHttpFile & set "FAILED=1")
"%BIN%\FormatHttpFile.exe" "%OUT%\formatted1.http" > "%OUT%\formatted2.http"
if errorlevel 1 (echo FAILED: FormatHttpFile, second pass & set "FAILED=1")
fc /b "%OUT%\formatted1.http" "%OUT%\formatted2.http" >nul
if errorlevel 1 (echo FAILED: formatting is not stable & set "FAILED=1")

echo -- RunHttpFile against a local server
set "CAN_RUN=1"
where python >nul 2>&1
if errorlevel 1 (echo skipped: python was not found & set "CAN_RUN=")
set "HAVE_CURL="
if exist "%BIN%\libcurl.dll" set "HAVE_CURL=1"
where libcurl.dll >nul 2>&1
if not errorlevel 1 set "HAVE_CURL=1"
if not defined HAVE_CURL (echo skipped: libcurl.dll was not found & set "CAN_RUN=")
if defined CAN_RUN call :run_server_sample
exit /b 0

:run_server_sample
set "SERVER_PID="
for /f "usebackq" %%I in (`powershell -NoProfile -Command "(Start-Process python -ArgumentList 'build\test_server.py','8099' -WindowStyle Hidden -PassThru).Id"`) do set "SERVER_PID=%%I"
if not defined SERVER_PID (
  echo FAILED: the test server did not start
  set "FAILED=1"
  exit /b 0
)
ping -n 3 127.0.0.1 >nul
"%BIN%\RunHttpFile.exe" examples\local.http > "%OUT%\run.txt"
if errorlevel 1 (echo FAILED: RunHttpFile & set "FAILED=1")
findstr /c:"Bearer tok-123" "%OUT%\run.txt" >nul
if errorlevel 1 (echo FAILED: the login header was not chained into getUser & set "FAILED=1")
findstr /c:"getUser -> HTTP/1.1 200" "%OUT%\run.txt" >nul
if errorlevel 1 (echo FAILED: getUser did not return 200 & set "FAILED=1")
taskkill /pid %SERVER_PID% /f >nul 2>&1
exit /b 0
