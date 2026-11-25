import std/[json, osproc, strutils, unittest]
import gemi_core

suite "modeloValido y claveValida":
  test "acepta nombres normales":
    check modeloValido("gemini-3.5-flash-lite")
  test "rechaza vacío, rutas y caracteres raros":
    check not modeloValido("")
    check not modeloValido("../x")
    check not modeloValido("a:b")
    check not modeloValido("a b")
    check not modeloValido("x".repeat(65))
  test "limpia y valida API keys":
    let k = limpiarClave("  \"CLAVE_FICTICIA_DE_PRUEBA_12345_-ok\"\n")
    check k == "CLAVE_FICTICIA_DE_PRUEBA_12345_-ok"
    check claveValida(k)
    check not claveValida("corta123")
    check not claveValida("clave con espacios 1234567890123")
    check not claveValida("ClaveConSalto\n123456789012345")

suite "separarArgs y config":
  test "separa opciones de argumentos literales tras --":
    let (o, l) = separarArgs(["-m", "gemini-3.5-flash-lite", "--", "-O2", "vs", "-O3"])
    check o == @["-m", "gemini-3.5-flash-lite"]
    check l == @["-O2", "vs", "-O3"]
  test "valorConfig lee con comillas y espacios":
    check valorConfig("  GEMINI_API_KEY=\"abc\" ", "GEMINI_API_KEY") == "abc"
    check valorConfig("OTRA=1", "GEMINI_API_KEY") == ""
    check valorConfig("# GEMINI_API_KEY=abc", "GEMINI_API_KEY") == ""
  test "actualizarConfig preserva otras claves y comentarios":
    let previo = "# Config local\nGEMINI_MODEL=gemini-3.5-flash-lite\nGEMINI_API_KEY=vieja\n"
    let nuevo = actualizarConfig(previo, "GEMINI_API_KEY", "ClaveFicticiaNueva_1234567890")
    check nuevo == "# Config local\nGEMINI_MODEL=gemini-3.5-flash-lite\nGEMINI_API_KEY=ClaveFicticiaNueva_1234567890\n"
    let conModelo = actualizarConfig(nuevo, "GEMINI_MODEL", "gemini-3.8-flash")
    check conModelo == "# Config local\nGEMINI_MODEL=gemini-3.8-flash\nGEMINI_API_KEY=ClaveFicticiaNueva_1234567890\n"
    check actualizarConfig("", "GEMINI_API_KEY", "ClaveFicticiaNueva_1234567890") ==
      "GEMINI_API_KEY=ClaveFicticiaNueva_1234567890\n"

suite "reintentable":
  test "solo 429, 500 y 503":
    check reintentable(429) and reintentable(503) and reintentable(500)
    check not reintentable(403) and not reintentable(404) and not reintentable(200)

suite "limpiar":
  test "quita secuencias de escape ANSI":
    check limpiar("hola\e[31mrojo\e[0m\r\nfin\x7f") == "hola[31mrojo[0m\nfin"
  test "conserva UTF-8, saltos y tabulaciones":
    check limpiar("¿Qué?\tsí\n") == "¿Qué?\tsí\n"

suite "ajustarAncho":
  test "no corta palabras por la mitad y respeta párrafos":
    let entrada = "Hola colega estamos probando que las palabras largas nunca se corten feas a mitad de línea.\n\nSegundo párrafo corto."
    let salida = ajustarAncho(entrada, 42)
    for l in salida.split('\n'):
      check l.len <= 48
    check "corten" in salida and "palabras" in salida
    check "\n\nSegundo párrafo corto." in salida
  test "alinea viñetas y no toca bloques de código":
    let entrada = "*   Elemento largo de lista que debe continuar alineado debajo sin romper palabras.\n```\nint linea_muy_larga_de_codigo_que_no_debe_partirse_jamas = 123456789;\n```"
    let salida = ajustarAncho(entrada, 45)
    let ls = salida.split('\n')
    check ls[0].startsWith("*   Elemento")
    check ls[1].startsWith("    ")
    check "int linea_muy_larga_de_codigo_que_no_debe_partirse_jamas = 123456789;" in salida

suite "extraerTexto":
  test "une varias partes":
    let r = extraerTexto("""{"candidates":[{"content":{"parts":[{"text":"a"},{"text":"b"}]}}]}""")
    check r.texto == "ab"
  test "ignora partes de pensamiento (thought=true)":
    let r = extraerTexto(
      """{"candidates":[{"content":{"parts":[{"thought":true,"text":"borrador interno"},{"text":"respuesta final"}]}}]}""")
    check r.texto == "respuesta final"
  test "bloqueo del prompt":
    let r = extraerTexto("""{"promptFeedback":{"blockReason":"SAFETY"}}""")
    check r.texto == "" and r.motivo == "bloqueado por SAFETY"
  test "finishReason sin texto":
    let r = extraerTexto("""{"candidates":[{"finishReason":"MAX_TOKENS"}]}""")
    check r.texto == "" and r.motivo == "finishReason=MAX_TOKENS"
  test "JSON inválido y vacío":
    check extraerTexto("<html>").motivo == "la respuesta no es JSON válido"
    check extraerTexto("<html>", enEs = false).motivo == "response is not valid JSON"
    check extraerTexto("{}").texto == ""
    check extraerTexto("{}", enEs = false).motivo == "no details"

suite "adjuntos y serialización":
  test "mime por extensión":
    check mimeBinario("a/B.PNG") == "image/png"
    check mimeBinario("x.jpeg") == "image/jpeg"
    check mimeBinario("x.pdf") == "application/pdf"
    check mimeBinario("x.c") == ""
  test "firma coincide con el tipo":
    check firmaValida("image/png", "\x89PNG\r\n\x1a\nresto")
    check firmaValida("image/webp", "RIFF1234WEBPdatos")
    check not firmaValida("image/pdf_mal", "%PDF-1.4")
    check firmaValida("application/pdf", "%PDF-1.4")
    check not firmaValida("image/png", "texto plano")
    check not firmaValida("image/jpeg", "")
    check not firmaValida("image/webp", "RIFF")
  test "esTexto detecta binarios":
    check esTexto("hola")
    check not esTexto("a\0b")
  test "partes y cuerpo producen JSON válido":
    let p1 = parteTexto("hola \"mundo\"\n2")
    let p2 = parteBinaria("image/png", "hi")
    check p2 == """{"inlineData":{"mimeType":"image/png","data":"aGk="}}"""
    let cuerpo = armarCuerpo([p1, p2])
    let j = parseJson(cuerpo)
    check j["contents"][0]["parts"][0]["text"].getStr() == "hola \"mundo\"\n2"
    check j["contents"][0]["parts"][1]["inlineData"]["data"].getStr() == "aGk="
    check not j.hasKey("tools")
    let cuerpoWeb = armarCuerpo([p1], busquedaWeb = true)
    let jw = parseJson(cuerpoWeb)
    check jw["tools"][0].hasKey("google_search")

suite "leerHastaLimite en pipe real":
  test "lee más de 64 KB completos desde un pipe":
    let procPipe = startProcess("/bin/sh", args = ["-c", "head -c 250000 /dev/zero | tr '\\0' x"],
      options = {poStdErrToStdOut})
    defer: procPipe.close()
    var f: File
    check open(f, procPipe.outputHandle, fmRead)
    defer: f.close()
    let (datos, excedido) = leerHastaLimite(f, 300_000)
    check not excedido
    check datos.len == 250_000
    check datos[0] == 'x' and datos[^1] == 'x'
  test "detecta exceso sobre el límite":
    let procPipe = startProcess("/bin/sh", args = ["-c", "head -c 50000 /dev/zero | tr '\\0' y"],
      options = {poStdErrToStdOut})
    defer: procPipe.close()
    var f: File
    check open(f, procPipe.outputHandle, fmRead)
    defer: f.close()
    let (datos, excedido) = leerHastaLimite(f, 10_000)
    check excedido
    check datos.len == 0

suite "mensajeError e idioma y fuentes":
  test "extrae y recorta":
    check mensajeError("""{"error":{"message":"fallo"}}""") == "fallo"
    check mensajeError("no json") == ""
    check mensajeError("{\"error\":{\"message\":\"" & "x".repeat(500) & "\"}}").len == 200
  test "detectarEspanol usa inglés por defecto":
    check detectarEspanol("", "", "es_VE.UTF-8")
    check detectarEspanol("es_ES.UTF-8", "", "en_US.UTF-8")
    check not detectarEspanol("", "", "en_US.UTF-8")
    check not detectarEspanol("", "", "fr_FR.UTF-8")
    check not detectarEspanol("", "", "C")
    check not detectarEspanol("", "", "")
  test "extraerFuentes lee URLs válidas de groundingMetadata":
    let resp = """{"candidates":[{"groundingMetadata":{"groundingChunks":[
      {"web":{"uri":"https://kernel.org/","title":"Kernel"}},
      {"web":{"uri":"https://kernel.org/","title":"Kernel"}},
      {"web":{"uri":"javascript:alert(1)","title":"Malo"}}
    ]}}]}"""
    check extraerFuentes(resp) == @["Kernel (https://kernel.org/)"]
    check extraerFuentes("{}").len == 0
