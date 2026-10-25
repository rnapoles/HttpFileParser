#!/bin/sh
# Builds examples/DumpHttpFile (run from the project root)
set -e
mkdir -p build/out
fpc -Mdelphi -Fusrc -FUbuild/out -FEbuild/out examples/DumpHttpFile.dpr
echo "Run: build/out/DumpHttpFile examples/sample.http"
