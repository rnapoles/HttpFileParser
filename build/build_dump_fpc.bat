@echo off
rem Builds and runs the test suite with Delphi (rsvars.bat must have been called)
if not exist build\out mkdir build\out
fpc -Mdelphi -Fusrc -FUbuild\out -FEbuild\out examples\DumpHttpFile.dpr
::fpc -Mdelphi -Fusrc -Futests -FUbuild\out -FEbuild\out tests\HttpFileTests.dpr || exit \b 1
echo "Run: build\out\DumpHttpFile examples\sample.http"
build\out\DumpHttpFile.exe examples\sample.http
