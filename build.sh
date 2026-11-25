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
    "$NIM" c -d:mingw $FLAGS --cpu:amd64 -o:windows/gemi.exe src/gemi.nim
    ;;
  *)
    "$NIM" c $FLAGS -o:gemi src/gemi.nim
    ;;
esac
