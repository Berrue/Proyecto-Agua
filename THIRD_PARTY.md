# Terceros y licencias

El juego se publica en Steam, así que **cada línea de código y cada asset del repo
tiene que tener una licencia compatible con uso comercial**, verificada y anotada
aquí. Este archivo se actualiza en el mismo commit que introduce la dependencia,
nunca después.

## Regla de trabajo: vendorizar, nunca depender

Las bases del ecosistema de agua de Godot son casi todas de una sola persona y con
validación externa mínima (algunas tienen 2 estrellas y un único commit, y varias
declaran haber sido escritas con asistencia de IA). Por eso:

1. Se **copia** el código al repo, no se instala como dependencia viva.
2. Se anota **URL + commit hash + fecha + licencia** en la tabla de abajo.
3. Se **audita línea a línea** antes de construir nada encima.

Lo que tomamos prestado es la **arquitectura y el trabajo aburrido** (clipmap, LOD,
snapping de cámara, reloj de red), no algoritmos difíciles. La suma de Gerstner son
~30 líneas: si una base se pudre, se reescribe.

## Vendorizado actualmente

No hay código de terceros vendorizado: todo `addons/ocean/` es original de este
proyecto. Las tipografías de terceros se registran en su sección específica.

## Previsto (fases F2–F8 del plan)

| Qué | Origen | Licencia | Para qué |
|---|---|---|---|
| Patrón de clipmap y snapping de cámara | `Chrisknyfe/boujie_water_shader` | MIT | Malla al horizonte sin vertex swimming |
| Modelo de celdas por volumen | `ManickYoj/godot-ocean-waves-buoyancy` | MIT | Inundación progresiva por celda |
| Absorción de color y espuma de contacto | `Malidos/Stylized-Water-Shader` | CC0 | Donante de shader |
| Rampa de luz toon | `eldskald/godot4-cel-shader` | MIT | Rampa global compartida |
| Outline por stencil | `dmlary/godot-stencil-based-outline-compositor-effect` | MIT | Contorno solo en actores |
| Voz por proximidad | `goatchurchprime/two-voip-godot-4` | MIT | Opus + RNNoise |
| Cableado de voz posicional | `thegatesbrowser/godot-multiplayer` | MIT | Template de integración |
| Reloj de red (solo `NetworkTime`) | `foxssake/netfox` | MIT | Godot no trae reloj compartido |
| Transporte y lobby | GodotSteam (**Codeberg**) | MIT | Steam Datagram Relay |
| Props de greybox | Kenney Nature / Survival Kit | CC0 | Solo para playtests honestos |

⚠️ **GodotSteam: usar Codeberg, no GitHub.** El espejo de GitHub está *archivado* y
todos los tutoriales existentes apuntan ahí.

## Steam (vendorizado 24-ago-2026)

| Qué | Origen fijado | Licencia | Para qué |
|---|---|---|---|
| `addons/godotsteam/` (el wrapper: `libgodotsteam.windows.*.dll`, `.gdextension`, `editor/`) | [`godotsteam-4.22-gdextension-plugin-4.4.zip`](https://codeberg.org/godotsteam/godotsteam/releases/download/v4.22-gde/godotsteam-4.22-gdextension-plugin-4.4.zip), release `v4.22-gde` (22-ago-2026), SHA-256 `9095440e9ddc253946083a9ef59fd030d51ffdf495ee6ec552f52451f6e288c2`, descargado 2026-08-24 | MIT — copia literal en `addons/godotsteam/license.md` | Transporte y lobby por Steam (`SteamMultiplayerPeer`), fase R2 |
| `addons/godotsteam/win64/steam_api64.dll` | Redistribuible de Valve **incluido dentro de ese mismo zip** (Steamworks SDK 1.65) | **Steamworks SDK Access Agreement** — no es MIT | Es la librería que habla con el cliente de Steam; el wrapper por sí solo no hace nada |

⚠️ **La única excepción admitida a «se audita lo que entra».** `steam_api64.dll` es un
binario cerrado de Valve cuya licencia **prohíbe la ingeniería inversa**, así que no se
puede cumplir la regla 9 en su sentido literal. Se acepta a sabiendas porque publicar en
Steam no tiene otro camino, y se acota: se anota su origen exacto, no se modifica, y no se
usa para nada que no sea el transporte. El acuerdo es **intransferible y terminable por
Valve**, y para firmarlo hace falta cuenta de Steamworks (Steam Direct, 100 USD por
producto). **Decisión pendiente: a nombre de quién se firma.**

⚠️ **Se instaló SOLO win64** (8,2 MiB de los 104 MiB del zip). El manifiesto
`godotsteam.gdextension` está **recortado a mano** para listar únicamente lo presente —
no es el original —, porque dejar las siete plataformas listadas y ausentes rompe el
export con un error críptico. Recuperar cualquiera es descomprimir su carpeta del zip y
devolver su línea. El resto (android, macOS, linux×3, win32) no se puede ni probar hoy:
el toolchain del repo es Windows entero.

⚠️ **La licencia del wrapper podría cambiar.** El mantenedor anunció por escrito
(24-jun-2026) que quiere restringir GodotSteam y que solo lo ha aplazado «hasta cerca de
Godot 5». Un cambio futuro no es retroactivo sobre esta copia — pero solo mientras se
pueda demostrar cuál era, que es para lo que están el SHA-256 y la copia literal del MIT.

## Tipografías

| Qué | Origen fijado | Licencia | Para qué |
|---|---|---|---|
| `assets/fonts/anybody/Anybody[wdth,wght].ttf` | `google/fonts` commit `ec626514f79f831f1ab848a82114a0ce7e2d6372`, descargado 2026-08-23 | SIL OFL 1.1 (`assets/fonts/anybody/OFL.txt`) | Voz Faena: impacto, actos y marca futura |
| `assets/fonts/atkinson-hyperlegible/*.ttf` | `googlefonts/atkinson-hyperlegible` commit `1cb311624b2ddf88e9e37873999d165a8cd28b46`, descargado 2026-08-23 | SIL OFL 1.1 (`assets/fonts/atkinson-hyperlegible/OFL.txt`) | Voz informativa legible en movimiento |
| `assets/fonts/noto-symbols/NotoSansSymbols[wght].ttf` | `google/fonts` commit `ec626514f79f831f1ab848a82114a0ce7e2d6372`, descargado 2026-08-23 | SIL OFL 1.1 (`assets/fonts/noto-symbols/OFL.txt`) | Reserva determinista para flechas y símbolos del HUD |

Las tres familias están vendorizadas sin modificar y sus textos OFL viven junto a
los binarios en el repositorio; no se depende de Google Fonts en runtime. Como el
proyecto todavía no tiene `export_presets.cfg`, la primera build distribuible debe
copiar esos `OFL.txt` junto al ejecutable o incluirlos explícitamente en cada preset.

## Música y audio

| Qué | Origen | Licencia | Para qué |
|---|---|---|---|
| `game/audio/music/oceanic_routine_loop.ogg` | ElevenLabs Music, plan Creator — generado 2026-08-23 | ⚠️ **Sin verificar** (ver abajo) | Cama musical de navegación, mar en calma |
| `game/audio/fishing/latigazo_lanzamiento.wav` | ElevenLabs SFX — generado 2026-08-23; se asume el mismo plan Creator del render musical, **confirmar** | ⚠️ **Sin verificar** (ver abajo) | El latigazo de la caña al lanzar |
| `game/audio/fishing/recogida_loop.wav` | ElevenLabs SFX — generado 2026-08-23; mismo plan por confirmar | ⚠️ **Sin verificar** (ver abajo) | Cama del forcejeo mientras traes al pez |

El resto del SFX de la caña (`game/audio/sfx_library.gd`) es **síntesis original
en tiempo de carga**: no necesita fila porque lo fabricamos nosotros al arrancar.

⚠️ **Verificación pendiente — bloquea la primera build pública.** ElevenLabs
publicita derechos de uso comercial sobre el audio generado en sus planes de
pago, pero el alcance exacto depende del plan y de la versión de los términos
vigente el día en que se generó. Antes de publicar en Steam:

1. Guardar en el repo una copia de los términos de ElevenLabs vigentes al
   **2026-08-23**, con la cláusula del plan Creator.
2. Confirmar que la licencia **sobrevive a la baja del plan**. Varios proveedores
   de IA generativa revocan los derechos comerciales cuando cancelás la
   suscripción, y estos audios tienen que poder seguir dentro del juego años
   después de que dejemos de pagar. Es el riesgo real de estas filas, no la
   generación.
3. Anotar el resultado acá y borrar este aviso.

El archivo del repo **no es el render original**: es el tramo 0:00–2:00 con un
crossfade equal-power de 4 s horneado en la cabeza para cerrar el loop (el porqué
está documentado en `game/audio/music_director.gd`). El render completo de 3:00
se guarda fuera del repo — si hay que rehacer el corte, hace falta ese original.

El **latigazo tampoco es el render crudo**. El original dura 0,68 s y trae dos
defectos: arranca con 75 ms de ruido de fondo (el golpe llegaba tarde respecto al
clic del jugador) y **termina cortado en el arranque de un segundo latigazo**, con
un salto de −23 dBFS a cero en seco — un click garantizado en cada lanzamiento. El
`.wav` del repo es el tramo 0,075–0,450 s con 2 ms de fundido de entrada y 20 ms
de salida, y se importa con `force/mono=true` (el estéreo original es dual-mono,
correlación 0,9997: el reproductor 3D lo colapsaría igual y ocuparía el doble). El
render original vive fuera del repo, como el de la música.

La **cama de recogida** tampoco es el render crudo: el original son 10,000 s que
al empalmarse en bucle dan un salto audible, así que el archivo del repo son 9,5 s
con un **wrap-crossfade equal-power de 0,5 s** — la cola fundida sobre la cabeza,
el mismo proceso que las camas de clima (`docs/CLIMA.md` §5). Medido: el salto en
la costura es 0,0066 contra 0,0288 de salto medio dentro del propio archivo, o sea
que el empalme es más continuo que el material. También va `force/mono=true`
(dual-mono, correlación 0,9940) y `edit/loop_mode=2`: el `.wav` no trae chunk
`smpl`, así que el loop lo fuerza el `.import` y lo protege
`tests/fishing_tests.tscn`. El nivel **no** está horneado — vive en
`FishingRod.HAUL_DB`.

## Lista negra — no entra en el repo

**Sin licencia (= todos los derechos reservados). Leer para aprender, jamás copiar:**

- `stvgale/Gerstner-Waves-Buoyancy-Effects-Godot-4` — `license = null` confirmado
- `jdupuy/whitecaps`
- `CBerry22/Buoyancy-in-Godot-4`
- `matthias-research/pages` — reimplementar desde los PDF, no copiar

**GPL / contaminante para un proyecto comercial:**

- Blender Ocean Modifier, Houdini Ocean Toolkit (GPL + FFTW)
- Basilisk, `sdthompson1/shallow-water-demo` (GPL-3.0)

**No redistribuible:**

- Ocean3D versión completa (licencia single-user: no puede vivir en el repo)
- Crest, UE5 Water plugin (EULA), NVIDIA WaveWorks, cualquier asset del Unity Asset Store

**Regla adicional:** ningún shader de `godotshaders.com` entra sin verificar su
licencia individual — allí la licencia es por autor y puede ser GPL v3, que
contaminaría el proyecto entero.

## Assets binarios

⚠️ El MIT del **código** de un repo **no cubre** sus `.obj`, skyboxes, `.wav` ni
texturas. Cualquier binario que venga con una base vendorizada se purga antes de la
primera build pública, no antes del release.
