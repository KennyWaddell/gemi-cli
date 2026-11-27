import std/[httpclient, json, net, os, parseopt, strutils, terminal]
import gemi_core
when defined(windows):
  import std/base64

const
  versionApp = "1.1.1"
  modeloPorDefecto = "gemini-3.5-flash-lite"
  modeloImagenPorDefecto = "gemini-3.1-flash-image"
  modelosRecomendados = [
    "gemini-3.5-flash-lite",
    "gemini-3.1-flash-lite",
    "gemini-3.8-flash",
    "gemma-4-31b-it",
    "gemma-4-26b-a4b-it"
  ]
  urlBase = "https://generativelanguage.googleapis.com/v1beta/models/"
  urlFiles = "https://generativelanguage.googleapis.com/v1beta/"
  urlUpload = "https://generativelanguage.googleapis.com/upload/v1beta/files"
  tamBloqueUpload = 1_048_576
  maxIntentos = 3
  usoEs = """Uso: gemi [-w] [-i] [-s regla] [-m modelo] [-f archivo] [--] "pregunta"
     cat archivo | gemi "pregunta"

  -i, --interactive  chat multi-turno en memoria (sin guardar en disco)
  -s, --system       instrucción de sistema fija para el modelo
  -w, --web          activa búsqueda en tiempo real con Google Search
  -m, --model        modelo a usar (sin valor abre selector; defecto """ & modeloPorDefecto & """)
      --models       muestra los 5 modelos ligeros recomendados
  -f, --file         adjunta archivo (se puede repetir). Texto (<=1 MB), imagen/PDF
                     (<=8 MB inline, o >8 MB hasta 100 MB y audio/vídeo vía File API)
  -o, --out          guarda la respuesta en .md o .txt (CRLF compatible con Windows)
      --img          genera una imagen y la guarda en el archivo indicado
      --set-key      configura o reemplaza tu GEMINI_API_KEY de forma oculta
      --set-model    guarda el modelo por defecto (sin valor abre selector)
  -v, --version      muestra la versión y modelo activo
  -c, --credits      muestra los créditos y el repositorio
  -h, --help         muestra esta ayuda

Clave (orden de prioridad):
  1. Variable de entorno GEMINI_API_KEY
  2. Usuario: ~/.config/gemi-cli/config (Linux) o %APPDATA%\gemi-cli\config (Windows, DPAPI)"""
  usoEn = """Usage: gemi [-w] [-i] [-s rule] [-m model] [-f file] [--] "prompt"
       cat file | gemi "prompt"

  -i, --interactive  in-memory multi-turn chat (no disk history)
  -s, --system       system instruction for the model
  -w, --web          enable real-time Google Search grounding
  -m, --model        model to use (no value opens selector; default: """ & modeloPorDefecto & """)
      --models       show the 5 recommended lightweight models
  -f, --file         attach a file; repeatable. Text (<=1 MB), image/PDF (<=8 MB
                     inline, or >8 MB up to 100 MB & audio/video via File API)
  -o, --out          save response to .md or .txt (Windows-friendly CRLF)
      --img          generate an image and save it to the given file path
      --set-key      set or update your GEMINI_API_KEY with hidden input
      --set-model    save default model in config (no value opens selector)
  -v, --version      show version and active model
  -c, --credits      show credits and repository
  -h, --help         show this help

API Key priority:
  1. GEMINI_API_KEY environment variable
  2. User config: ~/.config/gemi-cli/config (Linux) or %APPDATA%\gemi-cli\config (Windows, DPAPI)"""

when defined(windows):
  proc getUserDefaultUILanguage(): uint16 {.stdcall, dynlib: "kernel32", importc: "GetUserDefaultUILanguage".}
  proc getStdHandle(nStdHandle: int32): int {.stdcall, dynlib: "kernel32", importc: "GetStdHandle".}
  proc writeConsoleW(hConsoleOutput: int, lpBuffer: pointer, nNumberOfCharsToWrite: uint32,
                     lpNumberOfCharsWritten: ptr uint32, lpReserved: pointer): int32 {.
                     stdcall, dynlib: "kernel32", importc: "WriteConsoleW".}
  proc readConsoleW(hConsoleInput: int, lpBuffer: pointer, nNumberOfCharsToRead: uint32,
                    lpNumberOfCharsRead: ptr uint32, pInputControl: pointer): int32 {.
                    stdcall, dynlib: "kernel32", importc: "ReadConsoleW".}
  proc getConsoleProcessList(lpdwProcessList: ptr uint32, dwProcessCount: uint32): uint32 {.
                             stdcall, dynlib: "kernel32", importc: "GetConsoleProcessList".}
  proc getConsoleMode(hConsoleHandle: int, lpMode: ptr uint32): int32 {.
                      stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}
  proc setConsoleMode(hConsoleHandle: int, dwMode: uint32): int32 {.
                      stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}
  proc localFree(hMem: pointer): pointer {.stdcall, dynlib: "kernel32", importc: "LocalFree".}

  type
    DataBlob = object
      cbData: uint32
      pbData: ptr byte

  proc cryptProtectData(pDataIn: ptr DataBlob, szDataDescr: pointer,
                        pOptionalEntropy, pvReserved, pPromptStruct: pointer,
                        dwFlags: uint32, pDataOut: ptr DataBlob): int32 {.
                        stdcall, dynlib: "crypt32", importc: "CryptProtectData".}
  proc cryptUnprotectData(pDataIn: ptr DataBlob, ppszDataDescr: pointer,
                          pOptionalEntropy, pvReserved, pPromptStruct: pointer,
                          dwFlags: uint32, pDataOut: ptr DataBlob): int32 {.
                          stdcall, dynlib: "crypt32", importc: "CryptUnprotectData".}

  proc idiomaWindowsEs(): bool =
    (getUserDefaultUILanguage() and 0x03FF'u16) == 0x0A'u16

  proc consolaPropia(): bool =
    var pids: array[2, uint32]
    getConsoleProcessList(addr pids[0], 2'u32) == 1'u32

  proc escribirConsola(f: File, s: string) =
    if isatty(f):
      let h = getStdHandle(if f == stderr: -12'i32 else: -11'i32)
      let ws = newWideCString(s)
      let n = uint32(len(ws))
      var escritos: uint32 = 0
      if h != 0 and h != -1 and n > 0'u32:
        if writeConsoleW(h, addr ws[0], n, addr escritos, nil) != 0:
          return
    f.write s

  proc escribirLinea(f: File, s: string) =
    escribirConsola(f, s & "\n")

  proc leerLineaConsola(): string =
    if isatty(stdin):
      let h = getStdHandle(-10'i32)
      if h != 0 and h != -1:
        var buf: array[4096, Utf16Char]
        var leidos: uint32 = 0
        if readConsoleW(h, addr buf[0], uint32(buf.len - 1), addr leidos, nil) != 0:
          buf[int(leidos)] = Utf16Char(0'u16)
          result = $(cast[WideCString](addr buf[0]))
          return result.strip(leading = false, trailing = true, chars = {'\r', '\n'})
    stdin.readLine()

  proc leerClaveOculta(clave: var string): bool =
    let h = getStdHandle(-10'i32)
    var origMode: uint32 = 0
    var modoCambiado = false
    if h != 0 and h != -1 and getConsoleMode(h, addr origMode) != 0:
      let nuevo = (origMode or 0x0003'u32) and not 0x0004'u32
      modoCambiado = setConsoleMode(h, nuevo) != 0
    defer:
      if modoCambiado:
        discard setConsoleMode(h, origMode)
      escribirLinea(stdout, "")
    try:
      clave = leerLineaConsola()
      return true
    except EOFError, IOError:
      clave = ""
      return false
else:
  proc escribirConsola(f: File, s: string) = f.write s
  proc escribirLinea(f: File, s: string) = f.writeLine s
  proc leerLineaConsola(): string = stdin.readLine()

let enEs = detectarEspanol(
  getEnv("LC_ALL"),
  getEnv("LC_MESSAGES"),
  getEnv("LANG"),
  when defined(windows): idiomaWindowsEs() else: false)
proc tr(es, en: string): string = (if enEs: es else: en)
proc usoTexto(): string = (if enEs: usoEs else: usoEn)

var anchoEstado = 0
when defined(windows):
  var esperarAlSalir = false

proc estado(msg: string) =
  if isatty(stderr) and (msg.len > 0 or anchoEstado > 0):
    let borrar = max(anchoEstado, msg.len)
    escribirConsola(stderr, "\r" & spaces(borrar) & "\r" & msg)
    stderr.flushFile
    anchoEstado = msg.len

proc fallar(msg: string) {.noreturn.} =
  estado("")
  escribirLinea(stderr, "Error: " & limpiar(msg))
  when defined(windows):
    if esperarAlSalir:
      escribirLinea(stderr, "")
      escribirConsola(stderr, tr("Pulsa Enter para salir...", "Press Enter to exit..."))
      try:
        discard leerLineaConsola()
      except EOFError, IOError:
        discard
  quit 1

proc rutaConfigActiva(): string =
  getConfigDir() / "gemi-cli" / "config"

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

when defined(windows):
  const prefijoDpapi = "dpapi:"

  proc cifrarClaveWindows(clave: string): string =
    if clave.len == 0:
      return ""
    var entrada = DataBlob(cbData: uint32(clave.len), pbData: cast[ptr byte](unsafeAddr clave[0]))
    var salida: DataBlob
    if cryptProtectData(addr entrada, nil, nil, nil, nil, 0x1'u32, addr salida) == 0:
      fallar(tr("no se pudo cifrar la clave con DPAPI", "could not encrypt key with DPAPI"))
    defer:
      if salida.pbData != nil:
        discard localFree(salida.pbData)
    var bytes = newString(int(salida.cbData))
    if salida.cbData > 0'u32:
      copyMem(addr bytes[0], salida.pbData, int(salida.cbData))
    prefijoDpapi & encode(bytes)

  proc descifrarClaveWindows(valor: string): string =
    if not valor.startsWith(prefijoDpapi):
      return valor
    var crudo: string
    try:
      crudo = decode(valor[prefijoDpapi.len .. ^1])
    except ValueError:
      fallar(tr(
        "clave cifrada dañada en config; ejecuta 'gemi --set-key'",
        "corrupted encrypted key in config; run 'gemi --set-key'"))
    if crudo.len == 0:
      return ""
    var entrada = DataBlob(cbData: uint32(crudo.len), pbData: cast[ptr byte](unsafeAddr crudo[0]))
    var salida: DataBlob
    if cryptUnprotectData(addr entrada, nil, nil, nil, nil, 0x1'u32, addr salida) == 0:
      fallar(tr(
        "no se pudo descifrar GEMINI_API_KEY (¿otro usuario o PC?); ejecuta 'gemi --set-key'",
        "could not decrypt GEMINI_API_KEY (different user or PC?); run 'gemi --set-key'"))
    defer:
      if salida.pbData != nil:
        discard localFree(salida.pbData)
    result = newString(int(salida.cbData))
    if salida.cbData > 0'u32:
      copyMem(addr result[0], salida.pbData, int(salida.cbData))

proc valor(nombre: string): string =
  result = getEnv(nombre).strip()
  if result.len > 0:
    return
  let ruta = rutaConfigActiva()
  try:
    for linea in lines(ruta):
      result = valorConfig(linea, nombre)
      if result.len > 0:
        when defined(windows):
          if nombre == "GEMINI_API_KEY":
            result = descifrarClaveWindows(result)
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
    escribirLinea(stderr, tr("No se encontró GEMINI_API_KEY.", "GEMINI_API_KEY not found."))
    escribirLinea(stderr, tr(
      "Consigue una clave gratuita en: https://aistudio.google.com/apikey",
      "Get a free key at: https://aistudio.google.com/apikey"))
  var entrada = ""
  let promptClave = tr(
    "Pega tu GEMINI_API_KEY (entrada oculta) y pulsa Enter: ",
    "Paste your GEMINI_API_KEY (hidden input) and press Enter: ")
  escribirConsola(stdout, promptClave)
  stdout.flushFile
  let leida =
    when defined(windows):
      leerClaveOculta(entrada)
    else:
      readPasswordFromStdin("", entrada)
  if not leida:
    fallar(tr("entrada cancelada", "input cancelled"))
  when defined(windows):
    if '\x16' in entrada:
      fallar(tr(
        "en cmd.exe de Windows 7 usa clic derecho -> Pegar (Ctrl+V no pega)",
        "in Windows 7 cmd.exe use right-click -> Paste (Ctrl+V does not paste)"))
  let limpia = limpiarClave(entrada)
  if not claveValida(limpia):
    fallar(tr("formato de clave inválido: ", "invalid key format: ") &
      diagnosticoClave(limpia, enEs))
  let aGuardar =
    when defined(windows): cifrarClaveWindows(limpia)
    else: limpia
  guardarConfig(destino, "GEMINI_API_KEY", aGuardar)
  escribirLinea(stderr, tr("Clave guardada de forma segura en ", "Key saved securely to ") & destino)
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

proc crearContextoSsl(): SslContext =
  when defined(windows):
    let ca = getAppDir() / "cacert.pem"
    if not fileExists(ca):
      fallar(tr(
        "no se encontró cacert.pem junto al ejecutable: ",
        "cacert.pem not found next to executable: ") & ca)
    try:
      return newContext(verifyMode = CVerifyPeer, caFile = ca)
    except CatchableError as e:
      fallar(tr("no se pudo cargar cacert.pem: ", "could not load cacert.pem: ") & e.msg)
  else:
    newContext(verifyMode = CVerifyPeer)

proc subirArchivoResumable(ruta, mime, claveApi: string, tam: BiggestInt,
                           remotos: var seq[string]): string =
  let ctx = crearContextoSsl()
  defer: destroyContext(ctx)
  let cliente = newHttpClient(timeout = 60_000, maxRedirects = 0, sslContext = ctx)
  defer: cliente.close()

  let nombre = extractFilename(ruta)
  var meta = """{"file":{"displayName":"""
  escapeJson(nombre, meta)
  meta.add "}}"
  cliente.headers = newHttpHeaders({
    "x-goog-api-key": claveApi,
    "X-Goog-Upload-Protocol": "resumable",
    "X-Goog-Upload-Command": "start",
    "X-Goog-Upload-Header-Content-Length": $tam,
    "X-Goog-Upload-Header-Content-Type": mime,
    "Content-Type": "application/json"
  })
  estado(tr("Iniciando subida de ", "Starting upload of ") & nombre & "...")
  let inicio = cliente.post(urlUpload, meta)
  if int(inicio.code) notin 200 .. 299:
    fallar("File API start HTTP " & $int(inicio.code) & ": " & mensajeError(inicio.body))
  let uploadUrl = inicio.headers.getOrDefault("x-goog-upload-url").strip()
  if not uploadUrl.startsWith("https://generativelanguage.googleapis.com/"):
    fallar(tr("URL de subida inválida en File API", "Invalid File API upload URL"))

  var f: File
  if not open(f, ruta, fmRead):
    fallar(tr("no se puede abrir ", "cannot open ") & ruta)
  defer: f.close()

  var buf = newString(tamBloqueUpload)
  var offset: BiggestInt = 0
  var respCuerpo = ""
  while offset < tam:
    let n = f.readBuffer(addr buf[0], tamBloqueUpload)
    if n <= 0:
      break
    let ultimo = (offset + BiggestInt(n)) >= tam
    let cmd = if ultimo: "upload, finalize" else: "upload"
    let pct = int(((offset + BiggestInt(n)) * 100) div max(1'i64, tam))
    estado(tr("Subiendo ", "Uploading ") & nombre & " (" & $pct & "%)...")
    cliente.headers = newHttpHeaders({
      "X-Goog-Upload-Offset": $offset,
      "X-Goog-Upload-Command": cmd
    })
    let chunk = if n == tamBloqueUpload: buf else: buf[0 ..< n]
    let r = cliente.post(uploadUrl, chunk)
    if int(r.code) notin 200 .. 299:
      fallar("File API upload HTTP " & $int(r.code) & ": " & mensajeError(r.body))
    offset += BiggestInt(n)
    if ultimo:
      respCuerpo = r.body

  let info = extraerInfoArchivo(respCuerpo)
  if info.uri.len == 0 or info.nombre.len == 0:
    fallar(tr("File API no devolvió URI de archivo", "File API did not return file URI"))
  remotos.add info.nombre

  var st = info.estado
  var esperas = 0
  while st == "PROCESSING" and esperas < 30:
    estado(tr("Procesando archivo en Gemini...", "Processing file on Gemini..."))
    sleep(2000)
    inc esperas
    cliente.headers = newHttpHeaders({"x-goog-api-key": claveApi})
    let rg = cliente.get(urlFiles & info.nombre)
    if int(rg.code) in 200 .. 299:
      st = extraerInfoArchivo(rg.body).estado
  if st == "FAILED":
    fallar(tr("Gemini no pudo procesar el archivo ", "Gemini failed to process file ") & nombre)
  estado("")
  parteArchivoUri(mime, info.uri)

proc borrarArchivosRemotos(claveApi: string, remotos: seq[string]) =
  if remotos.len == 0:
    return
  try:
    let ctx = crearContextoSsl()
    defer: destroyContext(ctx)
    let cliente = newHttpClient(timeout = 10_000, maxRedirects = 0, sslContext = ctx)
    defer: cliente.close()
    cliente.headers = newHttpHeaders({"x-goog-api-key": claveApi})
    for nom in remotos:
      if nom.startsWith("files/"):
        discard cliente.request(urlFiles & nom, httpMethod = HttpDelete)
  except CatchableError:
    discard

proc cargarArchivo(ruta, claveApi: string, total: var int, remotos: var seq[string]): string =
  if not fileExists(ruta):
    fallar(tr("no existe el archivo ", "file not found: ") & ruta)
  let mimeBin = mimeBinario(ruta)
  let mimeMed = mimeMultimedia(ruta)
  let mime = if mimeMed.len > 0: mimeMed else: mimeBin
  var tam: BiggestInt
  try:
    tam = getFileSize(ruta)
  except OSError as e:
    fallar(tr("no se puede inspeccionar ", "cannot inspect ") & ruta & ": " & e.msg)
  if tam == 0:
    fallar(tr("el archivo está vacío: ", "file is empty: ") & ruta)

  let usarFileApi = mimeMed.len > 0 or (mimeBin.len > 0 and tam > maxBinario)
  if usarFileApi:
    if tam > maxFileApi:
      fallar(ruta & tr(" supera el límite de ", " exceeds limit of ") & $maxFileApi & " bytes")
    var f: File
    if not open(f, ruta, fmRead):
      fallar(tr("no se puede leer el archivo ", "cannot read file ") & ruta)
    var cab = newString(32)
    let leidos = f.readBuffer(addr cab[0], 32)
    f.close()
    cab.setLen(leidos)
    if not firmaValida(mime, cab):
      fallar(ruta & tr(" no parece un archivo ", " does not match signature for ") & mime)
    return subirArchivoResumable(ruta, mime, claveApi, tam, remotos)

  let limite = if mimeBin.len > 0: maxBinario else: maxTexto
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
  if mimeBin.len > 0:
    if not firmaValida(mimeBin, datos):
      fallar(ruta & tr(" no parece un archivo ", " does not match signature for ") & mimeBin)
    return parteBinaria(mimeBin, datos)
  if not esTexto(datos):
    fallar(ruta & tr(
      " es binario y su tipo no está soportado (png, jpg, webp, pdf, mp3, wav, ogg, m4a, flac, mp4, webm)",
      " is binary and its format is not supported (png, jpg, webp, pdf, mp3, wav, ogg, m4a, flac, mp4, webm)"))
  parteTexto(tr("Archivo ", "File ") & extractFilename(ruta) & ":\n" & datos)

proc mostrarModelos(activo: string) =
  escribirLinea(stdout, tr("Modelos recomendados:", "Recommended models:"))
  for i, m in modelosRecomendados:
    let marca = if m == activo: tr(" (activo)", " (active)") else: ""
    escribirLinea(stdout, "  " & $(i + 1) & ". " & m & marca)

proc elegirModelo(excluir, titulo: string): string =
  var opciones: seq[string]
  for m in modelosRecomendados:
    if m != excluir:
      opciones.add m
  escribirLinea(stderr, titulo)
  for i, m in opciones:
    escribirLinea(stderr, "  " & $(i + 1) & ". " & m)
  escribirLinea(stderr, "  0. " & tr("Cancelar", "Cancel"))
  escribirConsola(stderr, tr("Elige [1-", "Choose [1-") & $opciones.len &
    tr(", 0 para salir]: ", ", 0 to cancel]: "))
  stderr.flushFile
  var resp = ""
  try:
    resp = leerLineaConsola().strip()
  except EOFError, IOError:
    return ""
  if resp.len == 0 or resp == "0":
    return ""
  try:
    let idx = parseInt(resp)
    if idx in 1 .. opciones.len:
      return opciones[idx - 1]
  except ValueError:
    discard
  ""

proc enviar(clave, modelo, cuerpo: string): tuple[cuerpo, modeloUsado: string] =
  let ctx = crearContextoSsl()
  defer: destroyContext(ctx)
  let cliente = newHttpClient(timeout = 60_000, maxRedirects = 0, sslContext = ctx)
  defer: cliente.close()
  cliente.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "x-goog-api-key": clave})
  var modeloActual = modelo
  while true:
    let url = urlBase & modeloActual & ":generateContent"
    var cambiado = false
    for intento in 1 .. maxIntentos:
      var detalle: string
      var saturado = false
      try:
        estado(tr("Enviando a Gemini, espera un momento...", "Sending to Gemini, please wait..."))
        let resp = cliente.post(url, cuerpo)
        let codigo = int(resp.code)
        if codigo in 200 .. 299:
          estado("")
          return (resp.body, modeloActual)
        detalle = "HTTP " & $codigo & ": " & mensajeError(resp.body)
        if codigo in [429, 503]:
          saturado = true
        if not reintentable(codigo):
          fallar(detalle)
      except TimeoutError:
        fallar(tr(
          "Gemini no respondió en 60 s; prueba otro modelo con -m",
          "Gemini did not respond within 60 s; try another model with -m"))
      except CatchableError as e:
        detalle = tr("red: ", "network: ") & e.msg
      if intento == maxIntentos:
        if saturado and isatty(stdin) and isatty(stderr):
          estado("")
          escribirLinea(stderr, "Error: " & limpiar(detalle))
          let alt = elegirModelo(modeloActual, tr(
            "Modelo saturado. ¿Reintentar con otro modelo?",
            "Model overloaded. Retry with another model?"))
          if alt.len > 0:
            modeloActual = alt
            cambiado = true
            break
          quit 1
        fallar(detalle)
      let aviso = tr("Reintentando (", "Retrying (") & $intento & "/" & $(maxIntentos - 1) & "): " &
        limpiar(detalle)
      if isatty(stderr):
        estado(aviso[0 .. min(aviso.high, 75)])
      else:
        escribirLinea(stderr, aviso)
      sleep(2000 * intento)
    if not cambiado:
      break

proc modeloActivo(flagModelo: string): string =
  if flagModelo.len > 0: return flagModelo
  result = valor("GEMINI_MODEL")
  if result.len == 0: result = modeloPorDefecto

proc mostrarCreditos() =
  escribirLinea(stdout, "gemi-cli " & versionApp & " - " &
    tr("Creado por Kenny Waddell", "Created by Kenny Waddell"))
  escribirLinea(stdout, tr("Repositorio: ", "Repository: ") & "https://github.com/KennyWaddell/gemi-cli")
  escribirLinea(stdout, tr("Licencia: GNU GPLv3", "License: GNU GPLv3"))

proc mostrarVersionTexto(modeloFlag: string) =
  escribirLinea(stdout, "gemi-cli " & versionApp & " (" & tr("modelo: ", "model: ") &
    limpiar(modeloActivo(modeloFlag)) & ")")

proc construirPartes(datosStdin, claveApi: string, archivos, palabras: seq[string],
                     remotos: var seq[string]): seq[string] =
  if datosStdin.len > 0:
    result.add parteTexto(tr("Entrada:\n", "Input:\n") & datosStdin)
  var total = 0
  for ruta in archivos:
    result.add cargarArchivo(ruta, claveApi, total, remotos)
  if palabras.len > 0:
    result.add parteTexto(palabras.join(" "))

proc guardarArchivoSalida(ruta, contenido: string) =
  try:
    writeFile(ruta, formatearSalidaArchivo(contenido, ruta))
    escribirLinea(stderr, tr("Guardado en ", "Saved to ") & ruta)
  except CatchableError as e:
    escribirLinea(stderr, tr("Error al guardar en ", "Error saving to ") & ruta & ": " & e.msg)

proc pedirRutaGuardar(arg: string): string =
  let limpio = arg.strip(chars = {' ', '\t', '"', '\''})
  if limpio.len > 0:
    return limpio
  escribirConsola(stdout, tr(
    "Archivo a guardar (.txt o .md, ej: notas.txt) [Enter = gemi-chat.md]: ",
    "Save file (.txt or .md, e.g. notes.txt) [Enter = gemi-chat.md]: "))
  stdout.flushFile
  try:
    let r = leerLineaConsola().strip(chars = {' ', '\t', '"', '\''})
    if r.len > 0: r else: "gemi-chat.md"
  except EOFError, IOError:
    ""

proc mostrarRespuesta(respuestaBruta: string, busquedaWeb: bool): string =
  let (texto, motivo) = extraerTexto(respuestaBruta, enEs)
  if texto.len == 0:
    fallar(tr("respuesta sin texto (", "empty response (") & motivo & ")")
  let limpio = limpiar(texto)
  if isatty(stdout):
    let cols = terminalWidth()
    let ancho = if cols > 8: cols - 4 else: 74
    when not defined(windows):
      escribirLinea(stdout, "")
    escribirLinea(stdout, ajustarAncho(formatearTerminal(limpio), ancho))
  else:
    escribirLinea(stdout, limpio)

  if busquedaWeb:
    let fuentes = extraerFuentes(respuestaBruta)
    if fuentes.len > 0:
      escribirLinea(stdout, "")
      escribirLinea(stdout, tr("Fuentes:", "Sources:"))
      for f in fuentes:
        escribirLinea(stdout, "- " & f)
    else:
      escribirLinea(stderr, tr(
        "[Aviso] El modelo respondió sin usar búsqueda web.",
        "[Note] Model answered without web search results."))
  texto

proc responderUnaVez(claveApi, modelo, sistema, rutaImagen, rutaSalida: string,
                     busquedaWeb: bool, datosStdin: string,
                     archivos, palabras: seq[string]): string =
  var remotos: seq[string]
  defer: borrarArchivosRemotos(claveApi, remotos)
  let partes = construirPartes(datosStdin, claveApi, archivos, palabras, remotos)
  let cuerpo = armarCuerpo(partes, busquedaWeb, sistema, generarImagen = rutaImagen.len > 0)
  let (respuestaBruta, _) = enviar(claveApi, modelo, cuerpo)
  if rutaImagen.len > 0:
    let img = extraerImagen(respuestaBruta)
    if img.datos.len > 0:
      try:
        writeFile(rutaImagen, img.datos)
      except CatchableError as e:
        fallar(tr("no se pudo guardar la imagen en ", "could not save image to ") & rutaImagen & ": " & e.msg)
      escribirLinea(stderr, tr("Imagen guardada en ", "Image saved to ") & rutaImagen & " (" & img.mime & ")")
      let (texto, _) = extraerTexto(respuestaBruta, enEs)
      if texto.len > 0:
        escribirLinea(stdout, limpiar(texto))
      return ""
    let (texto, motivo) = extraerTexto(respuestaBruta, enEs)
    if texto.len > 0:
      escribirLinea(stdout, limpiar(texto))
    fallar(tr("el modelo no devolvió ninguna imagen (", "model did not return an image (") & motivo & ")")
  result = mostrarRespuesta(respuestaBruta, busquedaWeb)
  if rutaSalida.len > 0:
    guardarArchivoSalida(rutaSalida, limpiar(result))

proc ejecutarChat(claveApi, modeloInicial, sistema, rutaSalida: string,
                  busquedaWeb: bool, partesIniciales: seq[string],
                  textoInicial: string) =
  var turnos: seq[Turno]
  var historial: seq[string]
  var modeloActual = modeloInicial
  escribirLinea(stdout, "gemi-cli " & versionApp & " [" & modeloActual & "]" & tr(
    " — chat en memoria (/save para guardar, exit o Enter vacío para salir)",
    " — in-memory chat (/save to export, exit or empty Enter to quit)"))
  if partesIniciales.len > 0:
    turnos.add ("user", partesIniciales)
    let cuerpo = armarCuerpoChat(turnos, busquedaWeb, sistema)
    let (resp, usado) = enviar(claveApi, modeloActual, cuerpo)
    modeloActual = usado
    let texto = mostrarRespuesta(resp, busquedaWeb)
    turnos.add ("model", @[parteTexto(texto)])
    if textoInicial.len > 0:
      historial.add "## " & tr("Tú", "You") & "\n" & textoInicial & "\n\n## Gemini\n" & limpiar(texto) & "\n"
    else:
      historial.add "## Gemini\n" & limpiar(texto) & "\n"
    escribirLinea(stdout, "")

  while true:
    escribirConsola(stdout, tr("Tú: ", "You: "))
    stdout.flushFile
    var entrada = ""
    try:
      entrada = leerLineaConsola().strip()
    except EOFError, IOError:
      break
    if entrada.len == 0 or entrada.toLowerAscii() in ["exit", "quit", "salir", "--exit", "--quit"]:
      break
    if entrada == "/save" or entrada == "/guardar" or
       entrada.startsWith("/save ") or entrada.startsWith("/guardar "):
      if historial.len == 0:
        escribirLinea(stderr, tr("Aún no hay respuestas para guardar.", "No responses to save yet."))
        continue
      let arg = if entrada.startsWith("/guardar"): entrada[8 .. ^1].strip() else: entrada[5 .. ^1].strip()
      let dest = pedirRutaGuardar(arg)
      if dest.len > 0:
        guardarArchivoSalida(dest, historial.join("\n"))
      continue
    turnos.add ("user", @[parteTexto(entrada)])
    let cuerpo = armarCuerpoChat(turnos, busquedaWeb, sistema)
    let (resp, usado) = enviar(claveApi, modeloActual, cuerpo)
    modeloActual = usado
    let texto = mostrarRespuesta(resp, busquedaWeb)
    turnos.add ("model", @[parteTexto(texto)])
    historial.add "## " & tr("Tú", "You") & "\n" & entrada & "\n\n## Gemini\n" & limpiar(texto) & "\n"
    escribirLinea(stdout, "")
  if rutaSalida.len > 0 and historial.len > 0:
    guardarArchivoSalida(rutaSalida, historial.join("\n"))

proc main() =
  var modelo, nuevoModelo, sistema, rutaImagen, rutaSalida: string
  var configurarClave = false
  var busquedaWeb = false
  var interactivo = false
  var mostrarVersion = false
  var archivos, palabras: seq[string]
  let (opts, literales) = separarArgs(commandLineParams())
  var p = initOptParser(opts,
    shortNoVal = {'h', 'v', 'w', 'c', 'i'},
    longNoVal = @["help", "version", "set-key", "web", "credits", "c", "models", "interactive"],
    mode = LaxMode)
  for tipo, clave, val in p.getopt():
    case tipo
    of cmdArgument:
      palabras.add clave
    of cmdShortOption, cmdLongOption:
      case clave
      of "i", "interactive":
        if val.len > 0: fallar(tr("-i no recibe argumentos", "-i does not take an argument"))
        interactivo = true
      of "s", "system":
        if val.len == 0: fallar(tr("-s necesita una instrucción", "-s requires a system instruction"))
        sistema = val
      of "img":
        if val.len == 0: fallar(tr("--img necesita una ruta de archivo", "--img requires an output file path"))
        rutaImagen = val
      of "o", "out":
        if val.len == 0: fallar(tr("-o necesita una ruta de archivo", "-o requires an output file path"))
        rutaSalida = val
      of "f", "file":
        if val.len == 0: fallar(tr("-f necesita un archivo", "-f requires a file"))
        archivos.add val
      of "m", "model":
        if val.len == 0:
          if isatty(stdin) and isatty(stderr):
            modelo = elegirModelo("", tr("Elige un modelo para esta consulta:", "Choose a model for this query:"))
            if modelo.len == 0: quit 1
          else:
            fallar(tr("-m necesita un modelo", "-m requires a model"))
        else:
          modelo = val
      of "models":
        mostrarModelos(modeloActivo(modelo))
        quit 0
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
        if val.len == 0:
          if isatty(stdin) and isatty(stderr):
            nuevoModelo = elegirModelo("", tr("Elige el modelo por defecto:", "Choose default model:"))
            if nuevoModelo.len == 0: quit 1
          else:
            fallar(tr("--set-model necesita un nombre de modelo", "--set-model requires a model name"))
        else:
          if not modeloValido(val): fallar(tr("nombre de modelo no válido", "invalid model name"))
          nuevoModelo = val
      of "v", "version":
        mostrarVersion = true
      of "c", "credits":
        mostrarCreditos()
        quit 0
      of "h", "help":
        escribirLinea(stdout, usoTexto())
        quit 0
      else:
        fallar(tr("opción desconocida: ", "unknown option: ") & clave)
    of cmdEnd:
      discard

  avisarPermisos(rutaConfigActiva())

  if mostrarVersion:
    mostrarVersionTexto(modelo)
    quit 0

  for lit in literales:
    palabras.add lit

  var datosStdin = ""
  if not isatty(stdin):
    datosStdin = leerStdin()

  if nuevoModelo.len > 0:
    let destino = rutaConfigActiva()
    guardarConfig(destino, "GEMINI_MODEL", nuevoModelo)
    escribirLinea(stderr, tr("Modelo por defecto guardado (", "Default model saved (") &
      nuevoModelo & tr(") en ", ") to ") & destino)

  if configurarClave:
    discard pedirYGuardarClave(esPrimeraVez = false)

  if (nuevoModelo.len > 0 or configurarClave) and not interactivo and
     datosStdin.len == 0 and archivos.len == 0 and palabras.len == 0:
    quit 0

  if interactivo:
    if not isatty(stdin):
      fallar(tr("-i requiere una terminal interactiva", "-i requires an interactive terminal"))
    var claveApi = valor("GEMINI_API_KEY")
    if claveApi.len == 0:
      claveApi = pedirYGuardarClave(esPrimeraVez = true)
    modelo = modeloActivo(modelo)
    if not modeloValido(modelo):
      fallar(tr("nombre de modelo no válido", "invalid model name"))
    var remotos: seq[string]
    defer: borrarArchivosRemotos(claveApi, remotos)
    let partesIni = construirPartes(datosStdin, claveApi, archivos, palabras, remotos)
    ejecutarChat(claveApi, modelo, sistema, rutaSalida, busquedaWeb, partesIni, palabras.join(" "))
    quit 0

  if datosStdin.len == 0 and archivos.len == 0 and palabras.len == 0:
    when defined(windows):
      if consolaPropia() and isatty(stdin):
        esperarAlSalir = true
        var historialWin: seq[string]
        escribirLinea(stdout, "gemi-cli " & versionApp & tr(
          " (--help para comandos, /save para guardar, exit o Enter vacío para salir)",
          " (--help for commands, /save to export, exit or empty Enter to quit)"))
        while true:
          escribirConsola(stdout, tr(
            "¿Qué le quieres preguntar a Gemini? ",
            "What would you like to ask Gemini? "))
          stdout.flushFile
          var entrada = ""
          try:
            entrada = leerLineaConsola().strip()
          except EOFError, IOError:
            entrada = ""
          if entrada.len == 0 or entrada.toLowerAscii() in ["exit", "quit", "salir", "--exit", "--quit"]:
            quit 0
          if entrada == "/save" or entrada == "/guardar" or
             entrada.startsWith("/save ") or entrada.startsWith("/guardar "):
            if historialWin.len == 0:
              escribirLinea(stderr, tr("Aún no hay respuestas para guardar.", "No responses to save yet."))
              continue
            let arg = if entrada.startsWith("/guardar"): entrada[8 .. ^1].strip() else: entrada[5 .. ^1].strip()
            let dest = pedirRutaGuardar(arg)
            if dest.len > 0:
              guardarArchivoSalida(dest, historialWin.join("\n"))
            continue
          case entrada
          of "--help", "-h", "--comandos":
            escribirLinea(stdout, "")
            escribirLinea(stdout, usoTexto())
            escribirLinea(stdout, "")
          of "--version", "-v":
            mostrarVersionTexto(modelo)
          of "--models":
            mostrarModelos(modeloActivo(modelo))
          of "-i", "--interactive":
            var claveApi = valor("GEMINI_API_KEY")
            if claveApi.len == 0:
              claveApi = pedirYGuardarClave(esPrimeraVez = true)
            let modActual = modeloActivo(modelo)
            if not modeloValido(modActual):
              fallar(tr("nombre de modelo no válido", "invalid model name"))
            ejecutarChat(claveApi, modActual, sistema, rutaSalida, busquedaWeb, @[], "")
            quit 0
          of "--credits", "-c":
            mostrarCreditos()
          of "--set-key":
            discard pedirYGuardarClave(esPrimeraVez = false)
          of "--set-model":
            let m = elegirModelo("", tr("Elige el modelo por defecto:", "Choose default model:"))
            if m.len > 0:
              let destino = rutaConfigActiva()
              guardarConfig(destino, "GEMINI_MODEL", m)
              escribirLinea(stderr, tr("Modelo por defecto guardado (", "Default model saved (") &
                m & tr(") en ", ") to ") & destino)
          else:
            if entrada.startsWith("--set-model "):
              let m = entrada[12 .. ^1].strip()
              if not modeloValido(m):
                escribirLinea(stderr, tr("Error: nombre de modelo no válido", "Error: invalid model name"))
              else:
                let destino = rutaConfigActiva()
                guardarConfig(destino, "GEMINI_MODEL", m)
                escribirLinea(stderr, tr("Modelo por defecto guardado (", "Default model saved (") &
                  m & tr(") en ", ") to ") & destino)
            else:
              var claveApi = valor("GEMINI_API_KEY")
              if claveApi.len == 0:
                claveApi = pedirYGuardarClave(esPrimeraVez = true)
              let modActual = modeloActivo(modelo)
              if not modeloValido(modActual):
                fallar(tr("nombre de modelo no válido", "invalid model name"))
              let respTxt = responderUnaVez(claveApi, modActual, sistema, "", "", busquedaWeb, "", @[], @[entrada])
              if respTxt.len > 0:
                historialWin.add "## " & tr("Tú", "You") & "\n" & entrada & "\n\n## Gemini\n" & limpiar(respTxt) & "\n"
              escribirLinea(stdout, "")
    if datosStdin.len == 0 and archivos.len == 0 and palabras.len == 0:
      escribirLinea(stderr, usoTexto())
      quit 1

  var claveApi = valor("GEMINI_API_KEY")
  if claveApi.len == 0:
    claveApi = pedirYGuardarClave(esPrimeraVez = true)

  if modelo.len == 0 and rutaImagen.len > 0:
    modelo = modeloImagenPorDefecto
  else:
    modelo = modeloActivo(modelo)
  if not modeloValido(modelo):
    fallar(tr("nombre de modelo no válido", "invalid model name"))

  discard responderUnaVez(claveApi, modelo, sistema, rutaImagen, rutaSalida, busquedaWeb, datosStdin, archivos, palabras)

main()
