#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"

if [ ! -x "$APP_DIR/gemi" ]; then
    echo "Compilando gemi..."
    "$APP_DIR/build.sh"
fi

mkdir -p "$BIN_DIR"
cp "$APP_DIR/gemi" "$BIN_DIR/gemi"
chmod 755 "$BIN_DIR/gemi"

echo "Instalado correctamente en $BIN_DIR/gemi"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "Nota: agrega '$BIN_DIR' a tu PATH para ejecutar 'gemi' desde cualquier carpeta."
fi
