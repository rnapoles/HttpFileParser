#!/bin/sh
# Builds examples/RunHttpFile (run from the project root); needs libcurl installed
set -e
mkdir -p build/out
fpc -Mdelphi -Fusrc -Fusrc/jsonpath -FUbuild/out -FEbuild/out examples/RunHttpFile.dpr
echo "Run: build/out/RunHttpFile examples/features.http"
