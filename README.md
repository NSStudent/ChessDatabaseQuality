# ChessDatabaseQuality

Calidad de bases de partidas de ajedrez en Swift: **duplicados** (exactos, subsumidos y casi duplicados), **jugadores** (nombres normalizados y alias «posiblemente la misma persona») y **validación** al importar con un informe de «salud de la base».

Pensado para el importador de una app de ajedrez y para una pantalla de mantenimiento de bases. Se inspira en el proceso de Lumbras Gigabase, en `pgn-extract` y en el emparejamiento de registros de Fellegi-Sunter (bloqueo + similitud + contexto).

- Swift 6, SPM, iOS 18 / macOS 15.
- Depende de [`fischer-core`](https://github.com/NSStudent/fischer-core) 0.4.0 para trocear el PGN (`PGNByteChunker`), leer etiquetas y resolver y jugar las jugadas.
- Un paso en streaming: el fichero se lee por bloques y cada lote de partidas se analiza en paralelo. Una partida rota se salta y se informa; **nunca se aborta el fichero**.

```sh
swift build
swift test                       # 39 tests, con fixtures
swift build -c release
.build/release/cdq analyze base.pgn --out informe/       # report.md, report.json, duplicates.json, aliases.json
.build/release/cdq fabricate fuente.pgn prueba.pgn --games 2000 --seed 7   # PGN con duplicados plantados (+ prueba.pgn.truth.json)
.build/release/cdq analyze prueba.pgn                    # si existe el .truth.json, añade la evaluación
.build/release/cdq players base.pgn --out alias.json     # solo etiquetas: alias de jugadores
```

## API

### Todo de una vez

```swift
import ChessDatabaseQuality

let analysis = try await DatabaseQualityAnalyzer().analyze(fileAt: url) { progress in
    print(progress.phase, progress.bytesRead, progress.gamesRead)
}
print(analysis.report.markdown())            // «Salud de la base» en Markdown
let json = try analysis.report.json()        // las mismas cifras en JSON

for group in analysis.duplicateGroups {      // DuplicateGroup: keeper + members (exact/subsumed/near)
    let proposal = try analysis.source.mergeProposal(for: group)   // lee las cabeceras del fichero por offset
    // proposal.tags: cabecera fusionada; proposal.remove; proposal.conflicts
}
for alias in analysis.aliasProposals where alias.confidence != .possible {
    print(alias.canonical.normalized, "←", alias.alias.normalized, alias.reasons)
}
for game in analysis.gameIssues { … }        // problemas de cada partida, con índice y offset
```

`QualityOptions` agrupa `ValidationOptions`, `DuplicateOptions` y `AliasOptions`, más el tamaño de lote, los hilos y el directorio temporal.

### Por piezas (para el importador o una `.mcbase`)

```swift
// Validación de una partida
let game = GameAnalyzer().analyze(chunk)     // chunk: PGNGameChunk de fischer-core
game.issues                                  // [ValidationIssue]; la partida queda cortada en la jugada ilegal
game.summary()                               // GameSummary para el detector

// Duplicados por lotes, memoria acotada
let detector = try DuplicateDetector(options: DuplicateOptions(), workDirectory: tmp)
for batch in batches { detector.add(batch) }  // [GameSummary] o DuplicateFingerprint ya calculadas en paralelo
let result = try detector.finish()            // groups + statistics

// Cabecera fusionada sin fichero PGN (p. ej. filas de SQLite)
let proposal = MergeProposalBuilder.proposal(for: group, tags: [id: ["Event": …]])

// Jugadores
let name = PlayerName("Wely, Loek van")       // surname ["van","wely"], given ["loek"]
name.normalized                               // "van wely, loek"
name.matchKey                                 // "vely,l"
var directory = PlayerDirectory()
directory.observe(name, fideID: 1000233, elo: 2650, year: 2024)
let aliases = directory.aliasProposals()
```

`GameSummary` admite cualquier origen: identificador del llamador, `PlayerKey` de cada jugador, fecha, puntuación de cabecera, `startHash` (FEN), jugadas codificadas en 16 bits (`GameSummary.encode(from:to:promotion:)`) y la clave de cada posición (`GameAnalyzer.positionKey(_:)`: piezas, turno, enroques y al paso solo si hay captura posible, como en Polyglot).

## Criterios

### Duplicados

Primero se empareja por **pareja normalizada**: `matchKey` de Blancas + `matchKey` de Negras (ver Jugadores). Dentro de cada pareja:

| Tipo | Regla | Detalles |
|---|---|---|
| **Exacto** | mismas jugadas desde la misma posición inicial | fechas compatibles (las partes conocidas coinciden: `2025.??.??` ≈ `2025.03.14`) o partida de ≥ 60 medias jugadas. Así un **empate corto repetido** entre los mismos jugadores en otra fecha no se toma por duplicado. |
| **Subsumido** | las jugadas de A son un prefijo estricto de las de B | A con ≥ 8 medias jugadas y fechas compatibles. B tiene más información (más jugadas); A cuelga de la más larga. Una partida cortada por jugada ilegal o sin final suele salir aquí. |
| **Casi duplicado (posición)** | misma posición en la ply 40, o en la última si la partida es más corta | mismo número de ply, ≥ 8 medias jugadas, fechas compatibles. |
| **Casi duplicado (MinHash)** | Jaccard estimado ≥ 0,8 entre los conjuntos de posiciones desde la ply 10 | 32 funciones hash, LSH de 8 bandas × 4 filas (umbral efectivo ≈ 0,59, recuperación ≈ 98,5 % a J = 0,8). Solo partidas con ≥ 20 posiciones tras la ply 10. Sirve **entre parejas distintas**: un jugador debe coincidir (misma clave, mismas palabras en otro orden o Jaro-Winkler ≥ 0,88) y el otro puede ser una errata (≥ 0,7 con la misma inicial, o un apellido contenido en el otro: `Garcia` / `Fernandez Garcia`) o desconocido; fechas compatibles. Los cubos de más de 64 partidas (teoría común) se descartan. |

Si falta un jugador (`?`, `NN`…) la partida solo se empareja con ≥ 30 medias jugadas.

Las relaciones se unen con *union-find*: cada grupo tiene un **keeper** (la partida libre con más jugadas y mejor cabecera) y cada miembro dice de quién es duplicado y por qué regla. Las cifras «a eliminar» cuentan miembros, como el informe de Lumbras.

**Propuesta de fusión** (`MergeProposalBuilder`): jugadas del keeper y, por etiqueta, el mejor valor del grupo. `Date` la más completa; `Event`, `Site` la más larga («evento completo»); `White`/`Black` la grafía más completa y con FIDE ID; FIDE ID, Elo, títulos y el resto, el del keeper o el primer valor real; `Result` el del keeper salvo `*`; `PlyCount` siempre del keeper. Los marcadores (`?`, `????.??.??`, vacío, Elo 0) nunca ganan. Los valores reales en desacuerdo se devuelven como `conflicts` (fechas incompatibles, Elo distintos, nombres con otra clave…).

**Memoria acotada.** `DuplicateDetector` vuelca cada partida a disco: 64 particiones por hash de pareja (registro con jugadas de 16 bits), un índice de bandas LSH en 16 particiones y dos ficheros de ancho fijo (metadatos de 32 bytes y firmas de 128 bytes) que se leen mapeados en memoria. En `finish()` carga **una partición cada vez**; dentro de cada pareja todo es lineal (hash de jugadas, hash rodante de cada prefijo para los subsumidos, diccionario por posición en la ply 40). En RAM quedan unos 10 bytes por partida (union-find, relación, «duplicado de», método) y 8 más mientras se forman los grupos, la tabla de nombres distintos y, en `DatabaseQualityAnalyzer`, 12 bytes por partida de offsets para releer cabeceras. Con 492 k partidas el proceso completo no pasa de 223 MB.

### Jugadores

`PlayerName` pliega el nombre (minúsculas, sin diacríticos, otros alfabetos a latino, `ß→ss`, `ø→o`, `ł→l`…), quita títulos (`GM`) y contexto entre paréntesis, y separa apellido y nombre:

- `Apellido, Nombre` y `Apellido, N.`: la coma manda; las partículas finales (`Wely, Loek van`) pasan al apellido.
- `Nombre Apellido`: el apellido es la última palabra más las partículas que la preceden (`Loek van Wely`); `M. Carlsen` y `Carlsen M` por las iniciales; las familias vietnamitas, chinas y coreanas habituales (`Nguyen Duc Tri`) van primero.
- Partículas fuera de la clave: `van, der, de, del, la, le, du, di, da, dos, von, ter, al, el, ben, bin, ibn, abu…`
- Transliteración (`NameFolding.transliterationKey`, salvo los apellidos asiáticos de la lista, porque en pinyin `Zhang`/`Yang`, `Zhu`/`Yu` y `Hou`/`Hu` son apellidos distintos): `shch/sch→sh`, `tsch/tch→ch`, `zh/dzh/dj→j`, `ks→x`, `kh→h`, `ph→f`, `th→t`, `ou→u`, `w→v`, `ue/oe/ae→u/o/a`, `-ff→v`, `j/y→i` y letras dobles a una: Sergey/Sergei/Sergej, Grischuk/Grishchuk, Karpow/Karpoff/Karpov, Toukmakov/Tukmakov, Jakovenko/Yakovenko, Müller/Mueller comparten clave.

Claves: `normalized` (`van wely, loek`, la grafía que se agrupa), `matchKey` (último apellido del núcleo transliterado + inicial transliterada: `vely,l`; para nombres de dos palabras con apellido asiático, sin orden: `le+yang` para `Yang, Le` y `Le Yang`), `blockKeys` y `tokenSetKey` (palabras completas sin orden: `Ding Liren` / `Liren Ding`).

**Alias** (`PlayerDirectory.aliasProposals`): se recoge cada grafía con sus FIDE ID, rango de Elo y años activos.

1. Misma **FIDE ID** → `certain`. La FIDE ID manda: dos grafías con FIDE ID distintas **nunca** se proponen.
2. **Bloqueo**: primeras 3 letras del apellido transliterado + inicial, últimas 3 + inicial, y conjunto de palabras. «Un apellido contiene al otro» solo cuenta si es su principio o su final (`Lopez Gil` / `Lopez`), no `Rodriguez Rodriguez` / `Saiz Rodriguez`. Los bloques de más de 400 grafías se parten por nombre de pila completo.
3. **Similitud**: 55 % apellido (1 si la clave coincide, 0,95 si uno contiene al otro, Jaro-Winkler si no) + 45 % nombres (la inicial vale por cualquier nombre con esa letra; Jaro-Winkler por nombre). Con solo iniciales el apellido debe puntuar ≥ 0,95. Umbral 0,92. Jaro-Winkler se calcula sobre la clave transliterada y sobre el apellido plegado, y vale el mayor.
4. **Contexto**: un hueco de Elo > 300 o de años > 20 descarta. `likely` si la similitud es ≥ 0,97 y Elo (≤ 150 de hueco) y años (≤ 2) concuerdan; si no, `possible`.
5. La canónica es la grafía con FIDE ID, sin iniciales, con más partidas.

### Validación

| Problema | Gravedad | Regla |
|---|---|---|
| `unreadableGame` | error | la sección de etiquetas no se puede leer (cabecera cortada): la partida se salta y se sigue con la siguiente |
| `invalidFEN` | error | `FEN` no válido; no se comprueban las jugadas |
| `illegalMove` | error | jugada ilegal, ambigua o ilegible: la partida se **corta** antes de ella y se marca (jugada, ply y motivo) |
| `resultContradictsMate` | warning | la posición final es mate y el resultado no da la victoria a quien mata |
| `resultContradictsStalemate` | warning | ahogado final con resultado decisivo |
| `noMovesDecisiveResult` | warning | 0 jugadas y `1-0`/`0-1` (posible incomparecencia) |
| `missingTermination` | warning | el movetext no acaba en resultado: PGN truncado |
| `resultTagMismatch` | warning | `Result` distinto del final del movetext |
| `unbalancedMovetext` | warning | `{` o `(` sin cerrar |
| `impossibleDate` | warning | mes 13, 30 de febrero, año < 1475 o posterior al año siguiente |
| `eloOutOfRange` | warning | Elo no numérico o fuera de 1000–2900 (`0` y vacío son «sin Elo») |
| `invalidResult` | warning | `Result` que no es `1-0`, `0-1`, `1/2-1/2` ni `*` |
| `plyCountMismatch` | info | `PlyCount` distinto de las jugadas leídas |
| `malformedDate` | info | fecha que no es `AAAA.MM.DD` |
| `missingRequiredTag` | info | falta una etiqueta del *seven tag roster* |

## Cifras

Medidas del 16 nov 2026 en un Mac de 10 núcleos y 32 GB, binario release, 10 hilos. **La máquina estaba compartida con otras sesiones que compilaban** (load average entre 250 y 800), así que el tiempo de pared no es representativo: doy también el de CPU, que apenas depende de la carga. Informes en `measurements/` (`report.md` y `report.json`; las listas completas de grupos y alias de Lumbras no se incluyen, se generan con `cdq analyze`).

### Lumbras Gigabase OTB 2025 (`~/Downloads/LumbrasGigabase_OTB_2025.pgn`)

| Medida | Valor |
|---|---|
| Partidas | 492.184 (496,9 MB) |
| CPU total | 366 s de usuario + 5 s de sistema ≈ **1.340 partidas por segundo de CPU** (leer, validar, jugar cada jugada, claves de posición, MinHash) |
| Tiempo de pared | 262 s con load ≈ 250–430; 671 s con load ≈ 800. Con la máquina libre se espera ≈ 45 s de lectura (CPU / 10 hilos) |
| Fases (última ejecución) | lectura y validación 602 s, duplicados 12 s (3,6 s con menos carga), alias 56 s (26 s con menos carga; un solo hilo) |
| Memoria máxima (RSS) | **182–223 MB** según la ejecución |

**Validación**: 490.846 partidas limpias (99,73 %), ninguna ilegible.

| Problema | Partidas | Ejemplo |
|---|---|---|
| Jugada ilegible | 2 | #62623 *Jammalamadaka – Kaufman*, SPICE Cup 2025: `1. d2d4`, la partida está en notación UCI |
| Resultado incoherente con el mate | 116 | #326 *Musenze – Lakica*, Kireka Juniors 2025: mate de las blancas y `0-1` |
| Resultado decisivo con ahogado | 8 | #136418 *Gomes Barranco – Garcia Marroquin*: ahogado y `1-0` |
| Elo fuera de 1000–2900 | 1.214 | #1236, Bundesliga U10: `BlackElo 815` (Elo nacional por debajo del suelo FIDE) |

**Duplicados**: Lumbras ya viene deduplicada, pero todavía aparecen **5.628 grupos** con 5.739 partidas sobrantes (1,2 %): sobre todo la misma partida importada de dos fuentes (`Source` «Legacy Software Dump» y «LichessBroadcastAPI») con nombres de evento distintos («Barcelona Christmas IM» / «Cerrado IM Barcelona Navidad 2025»), rondas `7.2` / `7` o un día de diferencia.

| Tipo | Partidas a eliminar |
|---|---|
| Exactos | 2.429 |
| Subsumidos | 2.198 (p. ej. la misma partida con 83 y 82 medias jugadas) |
| Casi duplicados por posición en la ply 40 | 135 |
| Casi duplicados por MinHash | 977 (p. ej. `Goumas, G` / `Gkoumas, Georgios`; `Zeynalov, Rustam` / `Zeynalli, Rashad` con el mismo rival, ronda y jugadas) |

478.487 partidas tienen firma MinHash; el LSH verificó 51.819 pares candidatos y no descartó ningún cubo por grande. Una muestra al azar de 8 casi duplicados por MinHash y 4 exactos resultó ser 12/12 duplicados verdaderos.

**Jugadores**: 86.332 grafías distintas. 0 alias `certain` (Lumbras ya unifica los nombres por FIDE ID), **1.273 `likely`** y 3.639 `possible`. En una muestra, los `likely` son casi siempre la misma persona (`Parligras, Mircea-Emilian` / `Parligras, M`; `Sklokin-Bagiyan, Sergey` / `Sklokin, Sergey`; `Bagwe Gaurang` / `Bagwe, Gaurang`); los `possible` son para revisar a mano (aciertos como `Chacon Landinez, Cesar David` en otro orden, junto a falsos como `Cimburek, Jan` / `Jan Jurek`).

### PGN fabricado con verdad plantada

`cdq fabricate` toma 2.000 partidas limpias de Lumbras (≥ 50 medias jugadas, jugadores conocidos, fecha completa) y añade copias: exactas (otro formato y saltos de línea, comentario, otra grafía: `Nombre Apellido`, `Apellido, N.`, mayúsculas, sin tildes, transliteración; sin FIDE ID; evento recortado), subsumidas (sin las últimas 4–20 medias jugadas y `*`), casi duplicadas por posición (mismas 42–46 medias jugadas y luego otras jugadas legales), casi duplicadas por MinHash (errata en el apellido de Blancas que cambia la clave), **empates cortos repetidos** (misma pareja y 16 medias jugadas en otra fecha: no deben agruparse) y partidas rotas.

| Plantado | Encontrado |
|---|---|
| Exactos | **250 / 250** |
| Subsumidos | **250 / 250** |
| Casi duplicados por posición | **250 / 250** |
| Casi duplicados por MinHash | **250 / 250** |
| Empates repetidos agrupados (falsos positivos) | **0 / 250** |
| Validación: ilegibles, jugada ilegal, mate con resultado erróneo, 0 jugadas `1-0`, fecha imposible, sin final | 42, 42, 42, 42, 41, 41: todos detectados |

3.750 partidas en 5,2 s de pared (2,7 s de CPU) y 34 MB de RSS. El único grupo que une dos originales es un duplicado real de Lumbras: *Moskalenko – Cesar Maestre*, Barcelona Navidad 2025, con 83 y 82 medias jugadas. Las copias cortadas por jugada ilegal o sin final salen como subsumidas, que es correcto.

### Límites conocidos

- Apellidos de 2–3 letras con una errata (`Zhu` / `Zhru`) quedan por debajo de Jaro-Winkler 0,7 y no se emparejan por MinHash.
- El orden de un nombre sin coma es ambiguo: `Nombre Apellido1 Apellido2` se lee con apellido `Apellido2`; por eso la clave de emparejamiento usa el último apellido del núcleo. `Ding Yu Toh` / `Toh, Ding Yu` solo se encuentra por MinHash (mismas palabras).
- `possible` tiene bastante ruido; para limpiar una base de forma automática, usar solo `certain` y `likely`.
- El rango de Elo por defecto es el de la FIDE; una base con Elos nacionales debe ampliar `ValidationOptions.eloRange`.
- Las propuestas de alias son de un solo hilo (26–56 s para 86 k grafías).

## Estructura

```
Sources/ChessDatabaseQuality/
  Players/      NameFolding, PlayerName, JaroWinkler, PlayerDirectory (alias)
  Duplicates/   GameSummary, DuplicateFingerprint, MinHash, DuplicateDetector, MergeProposal
  Validation/   ValidationIssue, HealthReport
  Scan/         MovetextScanner, GameAnalyzer (tags, jugadas, clave de posición)
  Pipeline/     DatabaseQualityAnalyzer, SourceGameReader, QualityReport (Markdown/JSON)
  Fabrication/  Fabricator (PGN de prueba con verdad plantada) y su evaluación
  Support/      StableHash, PGNDate, BinaryIO
Sources/cdq/    CLI: analyze, fabricate, players
Tests/          39 tests (Swift Testing) con fixtures: sample.pgn (a mano) y 150 partidas de Lumbras
measurements/   informes de las medidas de este README
```

## Licencia

MIT, ver [LICENSE](LICENSE). El fixture `Tests/…/Fixtures/lumbras-sample.pgn` son las primeras 150 partidas de Lumbras Gigabase OTB 2025, usadas solo como datos de prueba.
