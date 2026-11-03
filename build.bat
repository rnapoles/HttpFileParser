@echo off
rem Builds the unit tests and the example programs.
rem   build.bat [fpc/delphi/all] [win32/win64]        defaults: all win64
rem Output: build\fpc-PLATFORM\bin and build\delphi-PLATFORM\bin (units in the obj folder next to bin).
rem Delphi: set RSVARS to the full path of rsvars.bat; it sets BDS, the RAD Studio folder.
rem FPC:    fpc.exe must be on the PATH (win32 needs the i386 compiler, win64 the x86_64 one).
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0scripts\env.bat" %*
if errorlevel 1 exit /b 2
cd /d "%ROOT%"

set "FAILED=0"
if /i "%COMPILER%"=="fpc" (
  call :build fpc
  if errorlevel 1 set "FAILED=1"
)
if /i "%COMPILER%"=="delphi" (
  call :build delphi
  if errorlevel 1 set "FAILED=1"
)
if /i "%COMPILER%"=="all" (
  call :build fpc
  if errorlevel 1 set "FAILED=1"
  call :build delphi
  if errorlevel 1 set "FAILED=1"
)
if "%FAILED%"=="0" (echo Build OK) else (echo Build FAILED)
exit /b %FAILED%

:build
set "TOOL=%~1"
set "OUTDIR=%ROOT%\build\%TOOL%-%PLATFORM%"
set "BIN=%OUTDIR%\bin"
set "OBJ=%OUTDIR%\obj"
if not exist "%BIN%" mkdir "%BIN%"
if not exist "%OBJ%" mkdir "%OBJ%"
echo ==== %TOOL% %PLATFORM% to build\%TOOL%-%PLATFORM%\bin
if /i "%TOOL%"=="fpc" (call :prepare_fpc) else (call :prepare_delphi)
if errorlevel 1 exit /b 1
for %%P in (%PROGRAMS%) do (
  echo     %%~nxP
  if /i "%TOOL%"=="fpc" (call :compile_fpc "%%P") else (call :compile_delphi "%%P")
  if errorlevel 1 exit /b 1
)
exit /b 0

:prepare_fpc
where fpc >nul 2>&1
if errorlevel 1 (
  echo fpc.exe was not found on the PATH
  exit /b 1
)
if /i "%PLATFORM%"=="win64" (set "FPC_TARGET=-Px86_64 -Twin64") else (set "FPC_TARGET=-Pi386 -Twin32")
exit /b 0

:compile_fpc
fpc %FPC_TARGET% -Mdelphi -vew -Fusrc -Fusrc\jsonpath -Fusrc\libcurl -Futests -FU"%OBJ%" -FE"%BIN%" "%~1.dpr"
exit /b %ERRORLEVEL%

:prepare_delphi
if defined RSVARS if exist "%RSVARS%" if not defined DELPHI_ENV_READY (
  call "%RSVARS%"
  set "DELPHI_ENV_READY=1"
)
if not defined BDS (
  echo BDS is not set. Set RSVARS to the full path of rsvars.bat and run again.
  exit /b 1
)
if /i "%PLATFORM%"=="win64" (set "DCC=%BDS%\bin\dcc64.exe") else (set "DCC=%BDS%\bin\dcc32.exe")
if not exist "%DCC%" (
  echo Compiler not found: %DCC%
  exit /b 1
)
exit /b 0

:compile_delphi
"%DCC%" -Q -CC -NS"System;System.Win;Winapi;Data" -U"src;src\jsonpath;src\libcurl;tests" -E"%BIN%" -N0"%OBJ%" "%~1.dpr"
exit /b %ERRORLEVEL%
