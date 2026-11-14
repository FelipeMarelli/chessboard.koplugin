# kindle-chess

Plugin de KOReader para leer libros de ajedrez en una Kindle con jailbreak: un tablero interactivo que se usa **dentro del libro**, sin salir de la página.

Estado (14 de noviembre de 2026): hay una prueba de concepto funcionando en el emulador de KOReader. Todavía no se probó en la Kindle real y no hay lógica de ajedrez (piezas, jugadas, reconocimiento de posiciones).

Lo que sigue por desarrollar está en `docs/historias.md` (historias de usuario del tablero flotante) y `docs/arquitectura.md` (decisiones técnicas, arquitectura y reglas de estilo).

## El problema

Los libros de ajedrez en e-reader traen diagramas estáticos y notación algebraica que hay que descifrar de cabeza; leer una página puede llevar diez minutos. La idea es que el lector tenga al lado un tablero donde ver la posición, pasar las jugadas y probar variantes mientras lee.

El sueño es que cada diagrama y cada secuencia de jugadas del libro se convierta sola en un tablero interactivo estilo lichess. Eso no es alcanzable para todos los libros, así que el soporte se piensa como una escalera.

## Escalera de soporte

Cada nivel funciona sin los de arriba.

| Nivel | Qué hace | Formatos |
|---|---|---|
| L0 | Tablero interactivo libre sobre el libro | Cualquiera |
| L1 | Tocar un diagrama y leer la posición desde la imagen | PDF, DjVu, EPUB |
| L2 | Tocar un diagrama que ya trae la posición (FEN) en un link | EPUB de Gambit |
| L3 | Recorrer la línea principal del texto | EPUB |
| L4 | Recorrer las variantes de las notas | EPUB; quizás con un preprocesador en la PC |

Prioridades acordadas:

- La mayoría de los libros son **PDF escaneados**, así que L0 y L1 son lo más valioso.
- Para EPUB, el mayor soporte que se pueda dar.
- Independiente del idioma del libro.
- Solo tener el tablero mientras se lee (L0) ya justifica el proyecto.

Ideas para L1, todavía sin probar sobre escaneos:

- El usuario señala el diagrama; no se intenta detectar todos los diagramas de la página.
- Aprendizaje por libro: el usuario corrige el primer diagrama y las plantillas de cada pieza se reutilizan para el resto del libro, en vez de una red neuronal general.
- El resultado siempre es editable; quién mueve y los enroques se indican con un botón.

## Qué existe hoy

- **En KOReader** hay nueve plugins de ajedrez en el catálogo de Storefront (entre ellos `ink_knight.koplugin`, cliente de Lichess con motor y problemas, y `casualkochess.koplugin`). Ninguno es un acompañante de lectura.
- **Fuera de e-ink**: chessvision.ai eBook Reader (web; PDF, EPUB y DjVu; clasifica cada casilla con una red neuronal) es el precedente más cercano. También Forward Chess, Gambit Chess Studio, los libros de ChessBase y Chessable, todos con formatos propios.

Funciones de Chess Studio que vale la pena copiar:

- Tocar una jugada del texto lleva a esa posición.
- Caja de variantes debajo del tablero, solo con las ramas de la posición actual.
- Flechas como historial y vuelta a la línea principal con un toque.
- Resaltar en el texto la jugada actual.
- Copiar la posición (FEN), por ejemplo para mandarla a Ink Knight.

No copiar: el texto que se desplaza solo (malo para el refresco de tinta) ni el motor.

## Libros de muestra

Están en la raíz del proyecto. Son los archivos de prueba; no modificarlos.

| Libro | Formato | Qué trae |
|---|---|---|
| Nunn's Chess Endings vol. 2 (Gambit) | EPUB | 963 diagramas GIF de 520×300; 958 envueltos en un link `https://lichess.org/analysis/<FEN>`. Línea principal en `<b>`. |
| Kasparov, My Great Predecessors 4 (Everyman) | EPUB | 655 diagramas JPG rayados de 415×360, sin FEN. Línea principal en `<span class="bold">`. Muchas partidas empiezan a mitad de juego. |
| The Modernized Sicilian Kan (Demuth) | EPUB | Cada jugada es un `<span name="gNmNvN">` (partida, jugada, variante). Trae campos ocultos `MOVETEXTn` con el texto completo de la partida y `FENn`. 627 diagramas PNG de 360×360. |
| The Petroff (Gambit) | PDF | 241 páginas escaneadas a 300 dpi en blanco y negro, sin capa de texto, dos columnas, figurines, diagramas limpios. |
| Bobby Fischer Teaches Chess | PDF | Páginas escaneadas, sin capa de texto, calidad pobre. |
| The Ultimate Closed Sicilian (Lane) | DjVu | 180 páginas escaneadas en gris, sin capa de texto, diagramas de bajo contraste. El más difícil. |

## Prueba de concepto

Tenía que responder dos preguntas de viabilidad:

1. ¿Puede un plugin dibujar un panel sobre la página que responda toques, sin que el resto de la página deje de funcionar?
2. ¿Puede un plugin leer lo que hay debajo de un toque: los píxeles de un diagrama y el texto con su marcado?

Las dos dan **sí**, en PDF, DjVu y EPUB.

### Qué hace el plugin

`chessbook.koplugin` agrega la entrada "Chess board panel" al menú del lector (sección de herramientas). Al activarla:

- Dibuja en la mitad inferior de la pantalla un tablero 8×8 vacío, un botón "Capturar", un botón "X" y una zona de estado.
- Tocar una casilla la marca y muestra su nombre.
- Tocar fuera del panel lo recibe el lector, como siempre (pasar de página, menús, links).
- "Capturar" colapsa el panel a una franja y espera un toque sobre la página. Ese toque lee lo que hay debajo, lo muestra en el panel y lo guarda en `emu-data/chessbook/` (un PNG por captura y `log.txt`).

### Cómo está hecho

- **Panel**: el plugin se registra como módulo de vista con `ReaderView:registerViewModule`, así que KOReader lo pinta después de la página. Una ventana normal (`UIManager:show`) no sirve, porque bloquea los toques al lector.
- **Toques**: una zona táctil a pantalla completa (`registerTouchZones`) que tiene prioridad sobre las zonas de toque del lector. El manejador devuelve `true` solo cuando el panel consume el toque; si no, el toque sigue su camino normal.
- **Píxeles en PDF y DjVu**: `screenToPageTransform` convierte el toque a coordenadas de página, `getPanelFromPage` (la detección de viñetas de cómic de KOReader) encuentra el recuadro que contiene el toque y `drawPagePart` lo renderiza.
- **Píxeles en EPUB**: `getImageFromPosition` devuelve la imagen bajo el toque.
- **Texto en EPUB**: `getWordFromPosition` da la palabra y su posición en el documento; `getHTMLFromXPointer` da el HTML del párrafo, con atributos; `getLinkFromPosition` da el link.

### Resultados

Verificado con toques sintéticos en el emulador, a 632×840 (media escala de una Paperwhite).

| Prueba | Resultado |
|---|---|
| Panel sobre la página | Se dibuja encima del libro. |
| Toque en el panel | Marca la casilla (e4) y no pasa de página. |
| Toque fuera del panel | El libro pasa de página con el panel abierto. |
| Píxeles, PDF (Petroff, pág. 30) | Tocar el diagrama devuelve el recorte exacto del tablero. |
| Píxeles, DjVu (Closed Sicilian, pág. 40) | Detecta y recorta el diagrama, pese al bajo contraste. |
| EPUB Nunn (pág. 100) | El diagrama devuelve la imagen y el link de lichess con el FEN (`7k/7p/3R4/1P6/3K4/8/8/2r5 b`). Una jugada devuelve la palabra y su HTML (`<b>2…Kg7</b>`). |
| EPUB Kan (pág. 40) | Una jugada devuelve el span con su identificador (`g5m30v4`). |
| EPUB Kasparov (pág. 80) | Devuelve la imagen del diagrama y la palabra tocada (`Qxf3`), sin marcado útil alrededor. |

### Hallazgos

- **El panel tapa media página**, incluido a veces el diagrama que se quiere tocar. Por eso se colapsa a una franja al capturar. El aspecto de la franja no se revisó en captura de pantalla; solo se comprobó que el flujo funciona.
- **Bug de KOReader en DjVu**: `drawPagePart` devuelve siempre la esquina superior izquierda de la página, porque el dibujado nativo de DjVu ignora la posición que recibe y solo respeta el desplazamiento del contexto de dibujo. El plugin renderiza DjVu por su cuenta (`renderPagePart`). El "panel zoom" de KOReader tiene el mismo problema en DjVu.
- **Links del Nunn**: tocar un diagrama sin "Capturar" abre el link de lichess, que es el comportamiento normal del lector. El plugin real tendrá que interceptar ese toque. El link ocupa todo el ancho de la línea, no solo la imagen.
- **Texto en PDF/DjVu**: si el toque no cae en un recuadro, el plugin devuelve un cuadrado fijo alrededor del toque (30 % del ancho de página).
- **Carpetas `.sdr`**: por defecto KOReader guarda su estado de lectura en una carpeta `.sdr` al lado de cada libro. El emulador quedó configurado para guardarlo en `emu-data/docsettings/` (`document_metadata_folder = "dir"` en `emu-data/settings.reader.lua`).

### Sin verificar

- Rendimiento y refresco de tinta en la Kindle real.
- Uso manual con mouse o dedo; todo se probó con toques inyectados.
- Reconocimiento de posiciones sobre diagramas escaneados. El experimento previo de plantillas acertó el 100 % en el Nunn, pero con imágenes digitales limpias y etiquetas tomadas del FEN embebido.
- Rotación de pantalla, modo scroll y zoom en PDF.

## Estructura del proyecto

```
chessbook.koplugin/     el plugin (_meta.lua, main.lua)
run-emu.sh              lanza el emulador con el plugin
emu-data/               datos del emulador (configuración, estado, capturas)
  run_pdf/ run_djvu/ run_nunn/ run_kan/ run_kasp/   resultados de la prueba
vendor/
  koreader-emu/         KOReader v2026.07.1 para Linux x86_64 (emulador)
  koreader-src/         fuentes de KOReader (commit 4184b73), solo para consulta
  koreader-base-src/    fuentes de koreader-base, solo para consulta
*.epub *.pdf *.djvu     libros de muestra
```

El plugin está enlazado con un symlink en `vendor/koreader-emu/lib/koreader/plugins/chessbook.koplugin`, así que los cambios en `chessbook.koplugin/` se ven al reiniciar el emulador.

## Cómo correrlo

A mano:

```sh
./run-emu.sh "The Petroff (Gambit Chess) (Lasha Janjgava) (z-library.sk, 1lib.sk, z-lib.sk).pdf"
```

Abrir el menú superior del lector, ir a la sección de herramientas y activar "Chess board panel".

El tamaño de la ventana se cambia con `EMULATE_READER_W`, `EMULATE_READER_H` y `EMULATE_READER_DPI` (por defecto 632, 840 y 150).

Prueba automática, sin tocar la ventana:

```sh
CHESSBOOK_SELFTEST=1 CHESSBOOK_PAGE=30 CHESSBOOK_TAPS="0.75,0.72" \
  ./run-emu.sh "$PWD/The Petroff (Gambit Chess) (Lasha Janjgava) (z-library.sk, 1lib.sk, z-lib.sk).pdf"
```

- `CHESSBOOK_PAGE`: página a la que ir.
- `CHESSBOOK_TAPS`: toques de captura, como fracciones de pantalla `x,y` separadas por `;`.

La prueba abre el panel, toca la casilla e4, comprueba que un toque fuera del panel pasa de página, hace las capturas pedidas y cierra. Deja capturas de pantalla (`shot_NN_*.png`), los recortes y `log.txt` en `emu-data/chessbook/`. La ruta del libro tiene que ser absoluta.

Toques usados en la prueba:

| Libro | Página | Toques |
|---|---|---|
| Petroff (PDF) | 30 | `0.75,0.72` (diagrama) |
| Closed Sicilian (DjVu) | 40 | `0.27,0.87` (diagrama) |
| Nunn (EPUB) | 100 | `0.5,0.5` (diagrama); `0.14,0.745` y `0.3,0.83` (jugadas) |
| Kan (EPUB) | 40 | `0.5,0.25` (diagrama); `0.5,0.6` y `0.4,0.8` (texto y jugada) |
| Kasparov (EPUB) | 80 | `0.5,0.25` (texto); `0.5,0.5` (diagrama) |

En los EPUB el número de página depende del tamaño de pantalla y de la fuente.

## Publicación en Storefront

Storefront (`ultimatejimmy/storefront.koplugin`) no tiene proceso de envío: arma su catálogo solo, buscando en GitHub. Para aparecer hace falta:

- Un repositorio con el topic `koreader-plugin` o con `.koplugin` en el nombre.
- Al menos un Release que no sea borrador, con un tag que empiece con dígito o con `v` y dígito. Los tags con alpha, beta, rc, dev, preview o test cuentan como prelanzamiento.
- Un `_meta.lua` con `version`, que se valida al instalar.
- Un `README.md`, que se muestra en el dispositivo.

Si el Release tiene un `.zip` adjunto se usa ese; si no, el zip automático del repositorio. El catálogo se ordena por estrellas y tiene votos de usuarios. AppStore (`omer-faruq/appstore.koplugin`) usa los mismos criterios.

## Pendientes

- Probar el plugin en la Kindle: rendimiento y refresco de pantalla.
- Probar el reconocimiento por plantillas sobre los recortes reales del PDF y el DjVu.
- Verificar el origen y la licencia de las piezas Merida y de la textura de madera (historia H03).

## Licencia

AGPL-3.0, la misma que KOReader. Ver `LICENSE`.
- Resolver la reconstrucción de jugadas desde el texto. En el experimento previo se resolvió el 90 % de la línea principal del Nunn y el 57 % del Kasparov, y "resuelta" solo significa que la jugada es legal en alguna posición candidata, no que sea la correcta. Los riesgos son el anclaje de la posición inicial, los errores en cascada y las diferencias entre editoriales.
