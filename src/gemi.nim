import std/[httpclient, net, os, parseopt, strutils, terminal]
import gemi_core

const
  versionApp = "1.0.0"
  modeloPorDefecto = "gemini-3.5-flash-lite"
  urlBase = "https://generativelanguage.googleapis.com/v1beta/models/"
  maxIntentos = 3
  usoEs = """Uso: gemi [-w] [-m modelo] [-f archivo] [--] "pregunta"
     cat archivo | gemi "pregunta"

  -w, --web          activa búsqueda en tiempo real con Google Search
  -m, --model        modelo a usar (por defecto """ & modeloPorDefecto & """)
  -f, --file         adjunta un archivo; se puede repetir. Texto (máx. 1 MB) o
                     png, jpg, webp, pdf (máx. 8 MB). Total máx. 16 MB
      --set-key      configura o reemplaza tu GEMINI_API_KEY de forma oculta
      --set-model    guarda el modelo por defecto en tu archivo de config
  -v, --version      muestra la versión y modelo activo
  -c, --credits      muestra los créditos y el repositorio
  -h, --help         muestra esta ayuda

Clave (orden de prioridad):
  1. Variable de entorno GEMINI_API_KEY
  2. Modo portable: gemi.cfg junto al ejecutable (si existe)
  3. Usuario: ~/.config/gemi-cli/config (Linux) o %APPDATA%\gemi-cli\config (Windows)"""
  usoEn = """Usage: gemi [-w] [-m model] [-f file] [--] "prompt"
       cat file | gemi "prompt"

  -w, --web          enable real-time Google Search grounding
  -m, --model        model to use (default: """ & modeloPorDefecto & """)
  -f, --file         attach a file; repeatable. Text (max 1 MB) or
                     png, jpg, webp, pdf (max 8 MB). Total max 16 MB
      --set-key      set or update your GEMINI_API_KEY with hidden input
      --set-model    save the default model in your config file
  -v, --version      show version and active model
  -c, --credits      show credits and repository
  -h, --help         show this help

API Key priority:
  1. GEMINI_API_KEY environment variable
  2. Portable mode: gemi.cfg next to the executable (if present)
  3. User config: ~/.config/gemi-cli/config (Linux) or %APPDATA%\gemi-cli\config (Windows)"""

let enEs = detectarEspanol(getEnv("LC_ALL"), getEnv("LC_MESSAGES"), getEnv("LANG"))
proc tr(es, en: string): string = (if enEs: es else: en)
proc usoTexto(): string = (if enEs: usoEs else: usoEn)

var anchoEstado = 0

proc estado(msg: string) =
  if isatty(stderr) and (msg.len > 0 or anchoEstado > 0):
    let borrar = max(anchoEstado, msg.len)
    stderr.write "\r" & spaces(borrar) & "\r" & msg
    stderr.flushFile
    anchoEstado = msg.len

proc fallar(msg: string) {.noreturn.} =
  estado("")
  stderr.writeLine "Error: " & limpiar(msg)
  quit 1

proc rutaPortable(): string =
  getAppDir() / "gemi.cfg"

proc rutaUsuario(): string =
  getConfigDir() / "gemi-cli" / "config"

proc rutaConfigActiva(): string =
  let port = rutaPortable()
  if fileExists(port): port else: rutaUsuario()

proc avisarPermisos(ruta: string) =
  when defined(posix):
    if fileExists(ruta):
      try:
        let p = getFilePermissions(ruta)
        if p * {fpGroupRead, fpGroupWrite, fpOthersRead, fpOthersWrite} != {}:
          stderr.writeLine tr(
            "Aviso: " & ruta & " es accesible por otros usuarios; ejecuta chmod 600",
            "Warning: " & ruta & " is readable by other users; run chmod 600")
      except OSError:
        discard

proc valor(nombre: string): string =
  result = getEnv(nombre).strip()
  if result.len > 0:
    return
  let ruta = rutaConfigActiva()
  try:
    for linea in lines(ruta):
      result = valorConfig(linea, nombre)
      if result.len > 0:
        return
  except IOError:
    discard

proc guardarConfig(ruta, campo, valor: string) =
  let dir = parentDir(ruta)
  createDir(dir)
  when defined(posix):
    try:
      setFilePermissions(dir, {fpUserRead, fpUserWrite, fpUserExec})
    except OSError:
      discard
  var previo = ""
  if fileExists(ruta):
    try:
      previo = readFile(ruta)
    except CatchableError as e:
      fallar(tr("no se pudo leer ", "could not read ") & ruta & ": " & e.msg)
  let nuevo = actualizarConfig(previo, campo, valor)
  let tmp = ruta & ".tmp"
  try:
    writeFile(tmp, "")
    when defined(posix):
      setFilePermissions(tmp, {fpUserRead, fpUserWrite})
    writeFile(tmp, nuevo)
    moveFile(tmp, ruta)
  except OSError as e:
    try: removeFile(tmp) except OSError: discard
    fallar(tr("no se pudo guardar la configuración en ", "could not save config to ") &
      ruta & ": " & e.msg)

proc pedirYGuardarClave(esPrimeraVez: bool): string =
  if not (isatty(stdin) and isatty(stdout) and isatty(stderr)):
    fallar(tr(
      "define GEMINI_API_KEY o ejecuta 'gemi --set-key' en una terminal interactiva",
      "set GEMINI_API_KEY or run 'gemi --set-key' in an interactive terminal"))
  let destino = rutaConfigActiva()
  if esPrimeraVez:
    stderr.writeLine tr("No se encontró GEMINI_API_KEY.", "GEMINI_API_KEY not found.")
    stderr.writeLine tr(
      "Consigue una clave gratuita en: https://aistudio.google.com/apikey",
      "Get a free key at: https://aistudio.google.com/apikey")
  var entrada = ""
  let promptClave = tr(
    "Pega tu GEMINI_API_KEY (entrada oculta) y pulsa Enter: ",
    "Paste your GEMINI_API_KEY (hidden input) and press Enter: ")
  if not readPasswordFromStdin(promptClave, entrada):
    fallar(tr("entrada cancelada", "input cancelled"))
  let limpia = limpiarClave(entrada)
  if not claveValida(limpia):
    fallar(tr(
      "formato de clave inválido (debe tener entre 20 y 256 caracteres alfanuméricos, '-' o '_')",
      "invalid key format (expected 20-256 alphanumeric, '-' or '_' characters)"))
  guardarConfig(destino, "GEMINI_API_KEY", limpia)
  stderr.writeLine tr("Clave guardada de forma segura en ", "Key saved securely to ") & destino
  limpia

proc leerStdin(): string =
  let (datos, excedido) = leerHastaLimite(stdin, maxTexto)
  if excedido:
    fallar(tr("la entrada por stdin supera ", "stdin input exceeds ") & $maxTexto & " bytes")
  if not esTexto(datos):
    fallar(tr(
      "la entrada por stdin es binaria; usa -f para imágenes y PDF",
      "stdin input is binary; use -f for images and PDFs"))
  datos

proc cargarArchivo(ruta: string, total: var int): string =
  if not fileExists(ruta):
    fallar(tr("no existe el archivo ", "file not found: ") & ruta)
  let mime = mimeBinario(ruta)
  let limite = if mime.len > 0: maxBinario else: maxTexto
  var tam: BiggestInt
  try:
    tam = getFileSize(ruta)
  except OSError as e:
    fallar(tr("no se puede inspeccionar ", "cannot inspect ") & ruta & ": " & e.msg)
  if tam == 0:
    fallar(tr("el archivo está vacío: ", "file is empty: ") & ruta)
  if tam > limite:
    fallar(ruta & tr(" supera ", " exceeds ") & $limite & " bytes")
  var datos: string
  try:
    datos = readFile(ruta)
  except IOError, OSError:
    fallar(tr("no se puede leer el archivo ", "cannot read file ") & ruta)
  total += datos.len
  if total > maxTotal:
    fallar(tr(
      "los adjuntos superan el total permitido (",
      "attachments exceed total allowed size (") & $maxTotal & " bytes)")
  if mime.len > 0:
    if not firmaValida(mime, datos):
      fallar(ruta & tr(" no parece un archivo ", " does not match signature for ") & mime)
    return parteBinaria(mime, datos)
  if not esTexto(datos):
    fallar(ruta & tr(
      " es binario y su tipo no está soportado (png, jpg, webp, pdf)",
      " is binary and its format is not supported (png, jpg, webp, pdf)"))
  parteTexto(tr("Archivo ", "File ") & extractFilename(ruta) & ":\n" & datos)

proc enviar(clave, modelo, cuerpo: string): string =
  let cliente = newHttpClient(timeout = 60_000, maxRedirects = 0)
  defer: cliente.close()
  cliente.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "x-goog-api-key": clave})
  let url = urlBase & modelo & ":generateContent"
  for intento in 1 .. maxIntentos:
    var detalle: string
    try:
      estado(tr("Enviando a Gemini, espera un momento...", "Sending to Gemini, please wait..."))
      let resp = cliente.post(url, cuerpo)
      let codigo = int(resp.code)
      if codigo in 200 .. 299:
        estado("")
        return resp.body
      detalle = "HTTP " & $codigo & ": " & mensajeError(resp.body)
      if not reintentable(codigo):
        fallar(detalle)
    except TimeoutError:
      fallar(tr(
        "Gemini no respondió en 60 s; prueba otro modelo con -m",
        "Gemini did not respond within 60 s; try another model with -m"))
    except CatchableError as e:
      detalle = tr("red: ", "network: ") & e.msg
    if intento == maxIntentos:
      fallar(detalle)
    let aviso = tr("Reintentando (", "Retrying (") & $intento & "/" & $(maxIntentos - 1) & "): " &
      limpiar(detalle)
    if isatty(stderr):
      estado(aviso[0 .. min(aviso.high, 75)])
    else:
      stderr.writeLine aviso
    sleep(2000 * intento)

proc modeloActivo(flagModelo: string): string =
  if flagModelo.len > 0: return flagModelo
  result = valor("GEMINI_MODEL")
  if result.len == 0: result = modeloPorDefecto

proc main() =
  var modelo, nuevoModelo: string
  var configurarClave = false
  var busquedaWeb = false
  var mostrarVersion = false
  var archivos, palabras: seq[string]
  let (opts, literales) = separarArgs(commandLineParams())
  var p = initOptParser(opts,
    shortNoVal = {'h', 'v', 'w', 'c'},
    longNoVal = @["help", "version", "set-key", "web", "credits", "c"],
    mode = LaxMode)
  for tipo, clave, val in p.getopt():
    case tipo
    of cmdArgument:
      palabras.add clave
    of cmdShortOption, cmdLongOption:
      case clave
      of "f", "file":
        if val.len == 0: fallar(tr("-f necesita un archivo", "-f requires a file"))
        archivos.add val
      of "m", "model":
        modelo = val
        if modelo.len == 0: fallar(tr("-m necesita un modelo", "-m requires a model"))
      of "w", "web":
        if val.len > 0: fallar(tr("-w no recibe argumentos", "-w does not take an argument"))
        busquedaWeb = true
      of "set-key":
        if val.len > 0:
          fallar(tr(
            "no pases la clave en el comando (queda en el historial); usa 'gemi --set-key' a secas",
            "do not pass the key on the command line (leaks in shell history); run 'gemi --set-key'"))
        configurarClave = true
      of "set-model":
        if val.len == 0: fallar(tr("--set-model necesita un nombre de modelo", "--set-model requires a model name"))
        if not modeloValido(val): fallar(tr("nombre de modelo no válido", "invalid model name"))
        nuevoModelo = val
      of "v", "version":
        mostrarVersion = true
      of "c", "credits":
        echo "gemi-cli " & versionApp & " - " &
          tr("Creado por Kenny Waddell", "Created by Kenny Waddell")
        echo tr("Repositorio: ", "Repository: ") & "https://github.com/KennyWaddell/gemi-cli"
        echo tr("Licencia: GNU GPLv3", "License: GNU GPLv3")
        quit 0
      of "h", "help":
        echo usoTexto()
        quit 0
      else:
        fallar(tr("opción desconocida: ", "unknown option: ") & clave)
    of cmdEnd:
      discard

  avisarPermisos(rutaConfigActiva())

  if mostrarVersion:
    echo "gemi-cli " & versionApp & " (" & tr("modelo: ", "model: ") &
      limpiar(modeloActivo(modelo)) & ")"
    quit 0

  for lit in literales:
    palabras.add lit

  var datosStdin = ""
  if not isatty(stdin):
    datosStdin = leerStdin()

  if nuevoModelo.len > 0:
    let destino = rutaConfigActiva()
    guardarConfig(destino, "GEMINI_MODEL", nuevoModelo)
    stderr.writeLine tr("Modelo por defecto guardado (", "Default model saved (") &
      nuevoModelo & tr(") en ", ") to ") & destino

  if configurarClave:
    discard pedirYGuardarClave(esPrimeraVez = false)

  if (nuevoModelo.len > 0 or configurarClave) and
     datosStdin.len == 0 and archivos.len == 0 and palabras.len == 0:
    quit 0

  if datosStdin.len == 0 and archivos.len == 0 and palabras.len == 0:
    stderr.writeLine usoTexto()
    quit 1

  var claveApi = valor("GEMINI_API_KEY")
  if claveApi.len == 0:
    claveApi = pedirYGuardarClave(esPrimeraVez = true)

  modelo = modeloActivo(modelo)
  if not modeloValido(modelo):
    fallar(tr("nombre de modelo no válido", "invalid model name"))

  let cuerpo = block:
    var partes: seq[string]
    if datosStdin.len > 0:
      partes.add parteTexto(tr("Entrada:\n", "Input:\n") & datosStdin)
    var total = 0
    for ruta in archivos:
      partes.add cargarArchivo(ruta, total)
    if palabras.len > 0:
      partes.add parteTexto(palabras.join(" "))
    armarCuerpo(partes, busquedaWeb)

  let respuestaBruta = enviar(claveApi, modelo, cuerpo)
  let (texto, motivo) = extraerTexto(respuestaBruta, enEs)
  if texto.len == 0:
    fallar(tr("respuesta sin texto (", "empty response (") & motivo & ")")
  let limpio = limpiar(texto)
  if isatty(stdout):
    let cols = terminalWidth()
    let ancho = if cols > 4: cols - 2 else: 80
    echo ajustarAncho(limpio, ancho)
  else:
    echo limpio

  if busquedaWeb:
    let fuentes = extraerFuentes(respuestaBruta)
    if fuentes.len > 0:
      echo ""
      echo tr("Fuentes:", "Sources:")
      for f in fuentes:
        echo "- " & f
    else:
      stderr.writeLine tr(
        "[Aviso] El modelo respondió sin usar búsqueda web.",
        "[Note] Model answered without web search results.")

main()
