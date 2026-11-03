@echo off
rem Builds, then runs the unit tests.
rem   test.bat [fpc/delphi/all] [win32/win64]         defaults: all win64
rem Exit code 0 only when every selected test run passes.
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0scripts\env.bat" %*
if errorlevel 1 exit /b 2
cd /d "%ROOT%"

call "%ROOT%\build.bat" %COMPILER% %PLATFORM%
if errorlevel 1 exit /b 1

set "FAILED=0"
if /i "%COMPILER%"=="fpc" call :run fpc
if /i "%COMPILER%"=="delphi" call :run delphi
if /i "%COMPILER%"=="all" (
  call :run fpc
  call :run delphi
)
if "%FAILED%"=="0" (echo ALL TESTS PASSED) else (echo TESTS FAILED)
exit /b %FAILED%

:run
rem the tests create and delete small fixture files in the current folder
set "WORK=%ROOT%\build\%~1-%PLATFORM%\work"
if not exist "%WORK%" mkdir "%WORK%"
echo ==== tests: %~1 %PLATFORM%
pushd "%WORK%"
"%ROOT%\build\%~1-%PLATFORM%\bin\HttpFileTests.exe"
if errorlevel 1 set "FAILED=1"
popd
exit /b 0
