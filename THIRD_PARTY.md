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

Nada todavía. Todo el código de `addons/ocean/` es original de este proyecto.

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
