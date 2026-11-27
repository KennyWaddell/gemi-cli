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

Practical Recipes (Pipes & Flags)
  1. Analyze your PC and save a clean .txt report (CRLF):
     systeminfo | gemi -o pc-report.txt "Rate this hardware"
  2. Diagnose network or running processes via pipe:
     ipconfig /all | gemi "Check if my DNS and network look normal"
     tasklist | gemi "Which processes are using the most resources?"
  3. List files in a folder and ask Gemini to organize or explain them:
     dir /b | gemi "Group these files by type"
  4. Compare two screenshots or analyze an error image:
     gemi -f img1.png -f img2.png "What changed between these two?"
  5. Search the web in real time with -w:
     gemi -w "Latest stable Windows 10 LTSC build number"
  6. Summarize a heavy PDF (>8 MB) or audio/video via File API:
     gemi -f voice_note.ogg "Transcribe and summarize"
  7. Start an in-memory chat with a fixed rule and export with /save:
     gemi -i -s "Short, step-by-step answers"

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

Recetas prácticas (Tuberías y comandos)
  1. Analizar tu PC y guardar un informe limpio en .txt (CRLF):
     systeminfo | gemi -o informe-pc.txt "Analiza este hardware"
  2. Diagnosticar red o procesos activos por tubería:
     ipconfig /all | gemi "¿Ves algún problema en mi red o DNS?"
     tasklist | gemi "¿Qué procesos destacan o consumen más?"
  3. Listar archivos de una carpeta para organizarlos o resumirlos:
     dir /b | gemi "Agrupa estos archivos por tipo"
  4. Comparar dos capturas o analizar un error en imagen:
     gemi -f cap1.png -f cap2.png "¿Qué cambió entre ambas?"
  5. Buscar en Internet en tiempo real con -w:
     gemi -w "¿Cuál es la última versión estable de Windows 10 LTSC?"
  6. Resumir un PDF pesado (>8 MB) o transcribir audio/vídeo (File API):
     gemi -f nota_voz.ogg "Transcribe y resume"
  7. Iniciar un chat en memoria con regla fija y exportarlo con /save:
     gemi -i -s "Respuestas cortas paso a paso"

Créditos y licencia
  Creado por Kenny Waddell
  Repositorio: https://github.com/KennyWaddell/gemi-cli
  Licencia: GNU GPLv3
