@echo off
rem Builds and runs the test suite with Delphi (rsvars.bat must have been called)
if not exist build\out mkdir build\out
fpc -Mdelphi -Fusrc -Fusrc\jsonpath -FUbuild\out -FEbuild\out examples\RunHttpFile.dpr
echo "Run: build/out/RunHttpFile examples/features.http"
build\out\RunHttpFile.exe examples\sample.http
