#!/bin/sh
set -eu
cd "$(dirname "$0")"
NIM="${NIM:-$HOME/nim/bin/nim}"
FLAGS="-d:ssl -d:release --mm:orc -d:strip --opt:size --path:src"

case "${1:-linux}" in
  test)
    "$NIM" c -r --hints:off --path:src -o:tests/test_core tests/test_core.nim
    rm -f tests/test_core
    ;;
  win)
    mkdir -p windows
    x86_64-w64-mingw32-windres windows/gemi.rc -O coff -o windows/gemi_res.o
    "$NIM" c -d:mingw -d:nimDontSetUtf8CodePage $FLAGS --cpu:amd64 --passL:windows/gemi_res.o -o:windows/gemi.exe src/gemi.nim
    rm -f windows/gemi_res.o
    ;;
  *)
    "$NIM" c $FLAGS -o:gemi src/gemi.nim
    ;;
esac
