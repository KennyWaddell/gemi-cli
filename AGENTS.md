# Reglas del Proyecto (Gemi-CLI)

- **Lenguaje y compilador:** Nim 2.x con `--mm:orc`, `-d:release`, `-d:strip` y `--opt:size`.
- **Cero dependencias externas:** Usar exclusivamente la libreria estandar (`std/*`). Prohibido agregar paquetes de `nimble`.
- **Hardware objetivo:** Equipos modestos (procesadores dual-core como Intel Celeron/Atom, 2 GB de RAM, discos mecanicos HDD), distribuciones ligeras de Linux (antiX, Debian, Alpine, etc.) y Windows 7 SP1, 8.1, 10 LTSB/LTSC y 11.
- **Estructura:**
  - `src/gemi_core.nim`: funciones puras (validacion, parseo JSON, firmas binarias, ajuste de ancho, lectura acotada de flujos).
  - `src/gemi.nim`: CLI, red HTTPS, configuracion local/portable y manejo de entrada/salida.
  - `tests/test_core.nim`: suite de pruebas unitarias y de tuberias.
- **Seguridad obligatoria:**
  - Nunca incluir claves API en el codigo ni aceptarlas como argumento visible en linea de comandos.
  - Mantener `maxRedirects = 0`, validacion TLS estricta, verificacion de magic bytes en adjuntos y limpieza de caracteres de control ANSI en la salida.
- **Verificacion:** Ejecutar `./build.sh test` y `./build.sh` tras cualquier cambio en `src/`, sin realizar llamadas innecesarias a la API real para no consumir cuota del usuario.
