import std/[base64, json, os, strutils, wordwrap]

const
  maxTexto* = 1_000_000
  maxBinario* = 8_000_000
  maxTotal* = 16_000_000
  maxFileApi* = 100_000_000

proc mimeBinario*(ruta: string): string =
  case splitFile(ruta).ext.toLowerAscii()
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".webp": "image/webp"
  of ".pdf": "application/pdf"
  else: ""

proc mimeMultimedia*(ruta: string): string =
  case splitFile(ruta).ext.toLowerAscii()
  of ".mp3": "audio/mpeg"
  of ".wav": "audio/wav"
  of ".ogg": "audio/ogg"
  of ".m4a": "audio/mp4"
  of ".flac": "audio/flac"
  of ".mp4": "video/mp4"
  of ".webm": "video/webm"
  else: ""

proc firmaValida*(mime, datos: string): bool =
  case mime
  of "image/png": datos.startsWith("\x89PNG\r\n\x1a\n")
  of "image/jpeg": datos.startsWith("\xFF\xD8\xFF")
  of "image/webp": datos.len >= 12 and datos[0 .. 3] == "RIFF" and datos[8 .. 11] == "WEBP"
  of "application/pdf": datos.startsWith("%PDF-")
  of "audio/mpeg":
    datos.startsWith("ID3") or
      (datos.len >= 2 and ord(datos[0]) == 0xFF and (ord(datos[1]) and 0xE0) == 0xE0)
  of "audio/wav": datos.len >= 12 and datos[0 .. 3] == "RIFF" and datos[8 .. 11] == "WAVE"
  of "audio/ogg": datos.startsWith("OggS")
  of "audio/flac": datos.startsWith("fLaC")
  of "audio/mp4", "video/mp4": datos.len >= 8 and datos[4 .. 7] == "ftyp"
  of "video/webm": datos.startsWith("\x1A\x45\xDF\xA3")
  else: false

proc esTexto*(datos: string): bool =
  '\0' notin datos

proc leerHastaLimite*(f: File, limite: int): tuple[datos: string, excedido: bool] =
  var buf: array[16384, char]
  while true:
    let n = f.readBuffer(addr buf[0], buf.len)
    if n <= 0:
      break
    if result.datos.len + n > limite:
      result.datos.setLen(0)
      return ("", true)
    let prev = result.datos.len
    result.datos.setLen(prev + n)
    copyMem(addr result.datos[prev], addr buf[0], n)

proc parteTexto*(s: string): string =
  result = newStringOfCap(s.len + 16)
  result.add """{"text":"""
  escapeJson(s, result)
  result.add "}"

proc parteBinaria*(mime, datos: string): string =
  let b64Len = ((datos.len + 2) div 3) * 4
  result = newStringOfCap(b64Len + mime.len + 44)
  result.add """{"inlineData":{"mimeType":""""
  result.add mime
  result.add """","data":""""
  result.add encode(datos)
  result.add """"}}"""

proc parteArchivoUri*(mime, fileUri: string): string =
  result = newStringOfCap(mime.len + fileUri.len + 48)
  result.add """{"fileData":{"mimeType":"""
  escapeJson(mime, result)
  result.add ""","fileUri":"""
  escapeJson(fileUri, result)
  result.add "}}"

proc extraerInfoArchivo*(cuerpo: string): tuple[uri, nombre, estado: string] =
  var j: JsonNode
  try:
    j = parseJson(cuerpo)
  except JsonParsingError, ValueError:
    return
  let f = if j.hasKey("file"): j["file"] else: j
  result.uri = f{"uri"}.getStr()
  result.nombre = f{"name"}.getStr()
  result.estado = f{"state"}.getStr()

type Turno* = tuple[rol: string, partes: seq[string]]

proc armarCuerpoChat*(turnos: openArray[Turno], busquedaWeb = false, sistema = "",
                      generarImagen = false): string =
  const sufijoWeb = ""","tools":[{"google_search":{}}]"""
  const sufijoImg = ""","generationConfig":{"responseModalities":["TEXT","IMAGE"]}"""
  var tam = 64
  if busquedaWeb: tam += 40
  if generarImagen: tam += 64
  if sistema.len > 0:
    tam += sistema.len + 48
  for t in turnos:
    tam += t.rol.len + 24
    for p in t.partes:
      tam += p.len + 1
  result = newStringOfCap(tam)
  result.add "{"
  if sistema.len > 0:
    result.add """"systemInstruction":{"parts":["""
    result.add parteTexto(sistema)
    result.add "]},"
  result.add """"contents":["""
  for ti, t in turnos:
    if ti > 0:
      result.add ","
    result.add """{"role":"""
    escapeJson(t.rol, result)
    result.add ""","parts":["""
    for pi, p in t.partes:
      if pi > 0:
        result.add ","
      result.add p
    result.add "]}"
  result.add "]"
  if busquedaWeb:
    result.add sufijoWeb
  if generarImagen:
    result.add sufijoImg
  result.add "}"

proc armarCuerpo*(partes: openArray[string], busquedaWeb = false, sistema = "",
                  generarImagen = false): string =
  armarCuerpoChat(@[("user", @partes)], busquedaWeb, sistema, generarImagen)

proc modeloValido*(m: string): bool =
  m.len in 1 .. 64 and m.allCharsInSet({'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '-', '_'})

proc limpiarClave*(k: string): string =
  k.strip(chars = {' ', '\t', '\r', '\n', '"', '\''})

const charsClave = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_', '.'}

proc claveValida*(k: string): bool =
  k.len in 20 .. 256 and k.allCharsInSet(charsClave)

proc diagnosticoClave*(k: string, enEs = true): string =
  if k.len == 0:
    return if enEs: "no se recibió texto (en cmd.exe usa clic derecho -> Pegar)"
           else: "no input received (in cmd.exe use right-click -> Paste)"
  if k.len < 20 or k.len > 256:
    return (if enEs: "longitud inválida: " else: "invalid length: ") &
      $k.len & (if enEs: " caracteres (se esperan 20-256)" else: " chars (expected 20-256)")
  for i, c in k:
    if c notin charsClave:
      return (if enEs: "carácter no válido en posición " else: "invalid character at position ") &
        $(i + 1) & " (ASCII " & $ord(c) & ")"
  ""

proc separarArgs*(params: openArray[string]): tuple[opciones, literales: seq[string]] =
  var trasDobleGuion = false
  for p in params:
    if not trasDobleGuion and p == "--":
      trasDobleGuion = true
      continue
    if trasDobleGuion:
      result.literales.add p
    else:
      result.opciones.add p

proc valorConfig*(linea, nombre: string): string =
  let l = linea.strip()
  if l.startsWith(nombre & "="):
    result = l[nombre.len + 1 .. ^1].strip(chars = {' ', '"', '\''})

proc actualizarConfig*(contenidoActual, campo, valor: string): string =
  var reemplazada = false
  var salida: seq[string]
  if contenidoActual.len > 0:
    for linea in contenidoActual.splitLines():
      if linea.strip().startsWith(campo & "="):
        if not reemplazada:
          salida.add campo & "=" & valor
          reemplazada = true
      else:
        salida.add linea
    while salida.len > 0 and salida[^1].len == 0:
      discard salida.pop()
  if not reemplazada:
    salida.add campo & "=" & valor
  result = salida.join("\n") & "\n"

proc reintentable*(codigo: int): bool =
  codigo in [429, 500, 503]

proc detectarEspanol*(lcAll, lcMsg, lang: string, porDefecto = false): bool =
  for v in [lcAll, lcMsg, lang]:
    let s = v.strip().toLowerAscii()
    if s.len > 0 and s != "c" and s != "posix":
      return s.startsWith("es")
  porDefecto

proc limpiar*(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    if (c >= ' ' and c != '\x7f') or c in {'\n', '\t'}:
      result.add c

proc ajustarAncho*(s: string, ancho: int): string =
  let tope = clamp(ancho, 40, 88)
  let lineas = s.split('\n')
  result = newStringOfCap(s.len + lineas.len * 4)
  var enCodigo = false
  for idx, linea in lineas:
    if idx > 0:
      result.add '\n'
    let recortada = linea.strip(leading = true, trailing = false)
    if recortada.startsWith("```"):
      enCodigo = not enCodigo
      result.add linea
      continue
    if enCodigo or recortada.len == 0:
      result.add linea
      continue
    let sangria = linea.len - recortada.len
    var prefijo = linea[0 ..< sangria]
    var cuerpo = recortada
    var cont = prefijo
    if (cuerpo.startsWith("* ") or cuerpo.startsWith("- ")) and cuerpo.len > 2:
      var extra = 2
      while extra < cuerpo.len and cuerpo[extra] == ' ':
        inc extra
      prefijo.add cuerpo[0 ..< extra]
      cuerpo = cuerpo[extra .. ^1]
      cont = spaces(prefijo.len)
    let util = max(20, tope - prefijo.len)
    result.add prefijo
    result.add wrapWords(cuerpo, maxLineWidth = util, splitLongWords = false,
      newLine = "\n" & cont)

proc extraerTexto*(cuerpo: string, enEs = true): tuple[texto, motivo: string] =
  var j: JsonNode
  try:
    j = parseJson(cuerpo)
  except JsonParsingError, ValueError:
    return ("", if enEs: "la respuesta no es JSON válido" else: "response is not valid JSON")
  for parte in j{"candidates"}{0}{"content"}{"parts"}.getElems():
    if not parte{"thought"}.getBool():
      result.texto.add parte{"text"}.getStr()
  let bloqueo = j{"promptFeedback"}{"blockReason"}.getStr()
  let fin = j{"candidates"}{0}{"finishReason"}.getStr()
  result.motivo =
    if bloqueo.len > 0: (if enEs: "bloqueado por " else: "blocked by ") & bloqueo
    elif fin.len > 0: "finishReason=" & fin
    else: (if enEs: "sin detalle" else: "no details")

proc extraerImagen*(cuerpo: string): tuple[mime, datos: string] =
  var j: JsonNode
  try:
    j = parseJson(cuerpo)
  except JsonParsingError, ValueError:
    return
  for parte in j{"candidates"}{0}{"content"}{"parts"}.getElems():
    let b64 = parte{"inlineData"}{"data"}.getStr()
    let mime = parte{"inlineData"}{"mimeType"}.getStr()
    if b64.len > 0 and mime in ["image/png", "image/jpeg", "image/webp"]:
      try:
        let raw = decode(b64)
        if firmaValida(mime, raw):
          return (mime, raw)
      except ValueError:
        discard

proc extraerFuentes*(cuerpo: string): seq[string] =
  var j: JsonNode
  try:
    j = parseJson(cuerpo)
  except JsonParsingError, ValueError:
    return
  for chunk in j{"candidates"}{0}{"groundingMetadata"}{"groundingChunks"}.getElems():
    let uri = limpiar(chunk{"web"}{"uri"}.getStr()).strip()
    if uri.startsWith("https://") or uri.startsWith("http://"):
      let titulo = limpiar(chunk{"web"}{"title"}.getStr()).strip()
      let linea = if titulo.len > 0: titulo & " (" & uri & ")" else: uri
      if linea notin result:
        result.add linea
        if result.len >= 5:
          break

proc mensajeError*(cuerpo: string): string =
  try:
    result = parseJson(cuerpo){"error"}{"message"}.getStr()
  except JsonParsingError, ValueError:
    discard
  if result.len > 200:
    result.setLen 200
