@echo off
rem Builds and runs the test suite with Free Pascal (run from the project root)
if not exist build\out mkdir build\out
fpc -Mdelphi -Fusrc -Futests -FUbuild\out -FEbuild\out tests\HttpFileTests.dpr || exit /b 1
pushd build\out & HttpFileTests.exe & popd
