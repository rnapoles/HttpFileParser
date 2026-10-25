#!/bin/sh
# Builds examples/ConvertHttpFile (run from the project root)
set -e
mkdir -p build/out
fpc -Mdelphi -Fusrc -FUbuild/out -FEbuild/out examples/ConvertHttpFile.dpr
echo "Run: build/out/ConvertHttpFile examples/sample.http postman out"
