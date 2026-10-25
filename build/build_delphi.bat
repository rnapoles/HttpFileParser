@echo off
rem Builds and runs the test suite with Delphi (rsvars.bat must have been called)
if not exist build\out mkdir build\out
dcc32 -U"src;tests" -NSSystem -E"build\out" -N0"build\out" tests\HttpFileTests.dpr || exit /b 1
build\out\HttpFileTests.exe
