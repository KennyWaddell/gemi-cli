================================================================================
gemi-cli v1.1.1 (Windows x64 Portable)
Lightweight Gemini CLI for modest hardware (Windows 7 SP1 / 8.1 / 10 / 11)
================================================================================

[ENGLISH]
--------------------------------------------------------------------------------
Quick Start
1. Keep these 4 files together in the same folder:
   - gemi.exe
   - cacert.pem
   - libssl-1_1-x64.dll
   - libcrypto-1_1-x64.dll
2. Double-click gemi.exe to ask questions directly, OR open cmd.exe / PowerShell
   in this folder and run:
     gemi "your question"
   (Optional: run install.bat to add this folder to your User PATH so you can
    run "gemi" from any cmd.exe / PowerShell window.)
3. On first run, paste your GEMINI_API_KEY (right-click -> Paste in Windows 7
   cmd.exe, then press Enter). Get a free key at:
     https://aistudio.google.com/apikey
   Your key is encrypted with Windows DPAPI and saved to:
     %APPDATA%\gemi-cli\config

Commands & Options
  gemi "prompt"               Ask Gemini a question
  gemi -i                     In-memory multi-turn chat (no disk history)
  gemi -s "rule" "prompt"     Set a fixed system instruction
  gemi -w "prompt"            Enable real-time Google Search grounding
  gemi -m <model> "prompt"    Use another model (or -m alone to pick from 5)
  gemi --models               List the 5 recommended lightweight models
  gemi -f <file> "prompt"     Attach text (<=1 MB), image/PDF (<=8 MB inline,
                              or >8 MB up to 100 MB & audio/video via File API)
  gemi -o out.txt "prompt"    Save response to .md or Windows CRLF .txt
  gemi --img out.png "prompt" Generate an image (requires *-image quota/billing)
  type file.txt | gemi "ask"  Read text from standard input (max 1 MB)
  systeminfo | gemi "ask"     Analyze your PC hardware via pipe
  gemi --set-key              Set or replace your GEMINI_API_KEY (hidden input)
  gemi --set-model <model>    Save default model to config (or omit to pick)
  gemi --version              Show version and active model
  gemi --credits              Show credits and repository
  gemi --help                 Show full help

  Note: When double-clicking gemi.exe, you can also type -i, --help, --models,
  /save [file_or_path] (e.g. /save notes.txt or /save C:\...\notes.txt,
  with or without quotes), --set-key, --set-model, --version, --credits, or exit.

Credits & License
  Created by Kenny Waddell
  Repository: https://github.com/KennyWaddell/gemi-cli
  License: GNU GPLv3


[ESPAÑOL]
--------------------------------------------------------------------------------
Inicio rápido
1. Mantén estos 4 archivos juntos en la misma carpeta:
   - gemi.exe
   - cacert.pem
   - libssl-1_1-x64.dll
   - libcrypto-1_1-x64.dll
2. Haz doble clic en gemi.exe para preguntar directamente, o abre cmd.exe /
   PowerShell en esta carpeta y ejecuta:
     gemi "tu pregunta"
   (Opcional: ejecuta install.bat para agregar esta carpeta al PATH de tu
    usuario y poder usar "gemi" desde cualquier ventana de cmd.exe / PowerShell.)
3. La primera vez, pega tu GEMINI_API_KEY (en cmd.exe de Windows 7 usa clic
   derecho -> Pegar y pulsa Enter). Consigue una clave gratuita en:
     https://aistudio.google.com/apikey
   Tu clave se guarda cifrada con Windows DPAPI en:
     %APPDATA%\gemi-cli\config

Comandos y opciones
  gemi "pregunta"             Hacer una consulta a Gemini
  gemi -i                     Chat multi-turno en memoria (sin guardar en disco)
  gemi -s "regla" "pregunta"  Fijar una instrucción de sistema para el modelo
  gemi -w "pregunta"          Activar búsqueda en tiempo real con Google Search
  gemi -m <modelo> "pregunta" Usar otro modelo (o -m solo para elegir entre 5)
  gemi --models               Mostrar los 5 modelos ligeros recomendados
  gemi -f <archivo> "preg."   Adjuntar texto (<=1 MB), imagen/PDF (<=8 MB inline,
                              o >8 MB hasta 100 MB y audio/vídeo vía File API)
  gemi -o nota.txt "preg."    Guardar respuesta en .md o .txt CRLF para Windows
  gemi --img out.png "preg."  Generar imagen (requiere cuota/billing *-image)
  type archivo.txt | gemi "p" Leer entrada desde tubería (máx. 1 MB)
  systeminfo | gemi "preg."   Analizar el hardware de tu PC por tubería
  gemi --set-key              Configurar o reemplazar GEMINI_API_KEY (entrada oculta)
  gemi --set-model <modelo>   Guardar modelo por defecto (o sin nombre para elegir)
  gemi --version              Mostrar versión y modelo activo
  gemi --credits              Mostrar créditos y repositorio
  gemi --help                 Mostrar la ayuda completa

  Nota: Al abrir gemi.exe con doble clic también puedes escribir -i, --help,
  --models, /save [archivo_o_ruta] (ej. /save notas.txt o /save C:\...\notas.txt,
  con o sin comillas), --set-key, --set-model, --version, --credits o exit.

Créditos y licencia
  Creado por Kenny Waddell
  Repositorio: https://github.com/KennyWaddell/gemi-cli
  Licencia: GNU GPLv3
