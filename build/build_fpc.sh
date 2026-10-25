#!/bin/sh
# Builds and runs the test suite with Free Pascal (run from the project root)
set -e
mkdir -p build/out
fpc -Mdelphi -Fusrc -Futests -FUbuild/out -FEbuild/out tests/HttpFileTests.dpr
(cd build/out && ./HttpFileTests)
