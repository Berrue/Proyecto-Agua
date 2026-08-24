# Proyecto Agua — Juego coop de supervivencia en mar extremo (Godot)

> **Cómo leer este documento (v2, 23-ago-2026).** Es el plan maestro F0–F8 redactado el
> 23-ago-2026, guardado con los **cinco fixes de la review independiente** del mismo día ya
> integrados: (1) olas rebeldes sin re-faseo, (2) regla 2 de flotabilidad reescrita, (3) la
> costura jugador↔barco↔red diseñada, (4) F1 con red mínima y agarre, (5) paridad CPU/GPU por
> golden vectors. El estado **vivo** del proyecto no se lleva aquí: fases y hallazgos en
> [DECISIONES.md](DECISIONES.md), mapa real del repo y reglas operativas en
> [../CLAUDE.md](../CLAUDE.md), diseño vivo en [DISENO.md](DISENO.md). Donde la realidad ya
> superó al plan (migración a 4.7.2 hecha, tsunami implementado como onda N con tiers, reloj
> `Ocean.sim_time` inyectado), el texto se alineó para no contradecir al repo. El árbol de
> ficheros de la sección de arquitectura es el **objetivo original**; el mapa real está en
> CLAUDE.md.

## Contexto

Queremos un **friendslop cooperativo** (línea PEAK / Lethal Company / R.E.P.O. / Content Warning) donde
**la simulación del agua es el sistema central y el antagonista**: el mar escala de calma a marejada, a
tormenta, a olas gigantes y termina en un **tsunami**. Somos una **tripulación de un barco pesquero**
atrapada en una travesía que empeora sin parar.

La pregunta que abrió el trabajo fue del usuario y es la correcta: *"¿por qué haríamos uno desde cero
cuando ya existe una base?"*. La investigación (13 agentes, ~35 URLs verificadas contra la API de GitHub
y las docs oficiales) responde: **no hay que escribirlo desde cero, pero tampoco existe una base que sirva
tal cual.** Hay ~8 repos MIT/CC0 que cubren el trabajo aburrido y caro (clipmap, LOD, snapping de cámara,
voz por proximidad, reloj de red). Lo que **nadie tiene** es exactamente nuestro pilar: un océano
determinista compartido por física y render, con un dial de furia continuo y un tsunami autorable.

### Punto de partida verificado

- `nuevo-proyecto-de-juego/project.godot` — Godot **4.6.1**, Forward+, Jolt, driver D3D12. Solo
  `project.godot` e `icon.svg`. Proyecto limpio, sin deuda, sin git.
- **Godot 4.7.2 es la estable actual** (18 ago 2026, verificado en godotengine.org/download/archive).
  4.6.x es rama muerta.

### Decisiones cerradas por el usuario

| Decisión | Elección | Consecuencia |
|---|---|---|
| Ambición | **Comercial en Steam** | Licencias limpias obligatorias; lobby por Steam; precio objetivo 3,99–5,99 USD |
| Fantasía | **Barco pesquero en tormenta** | Un solo `RigidBody3D` con sondas — nada de física de piezas. Roles de tripulación como bucle coop |
| Equipo | **Claude + usuario** | **Todo debe vivir en escenas** (`.tscn` / `.tres`), editable y ajustable desde el editor de Godot |
| Escenario | **Solo mar abierto** | Fuera: solver de aguas someras, terreno, batimetría, colisión de fondo. Elimina la mitad del riesgo técnico |
| Cámara | **Primera persona** | Coste de animación mínimo (modelo de producción de PEAK). Mitigar mareo con opciones desde el primer build |
| Motor | **Migrar a 4.7.2** | Cuesta cero hoy; trae el fix del bug de compute en D3D12 |
| Lenguaje | Lo decide la evidencia | **GDScript tipado** para v1 (ver más abajo); escotilla a C#/GDExtension solo si F2 lo mide necesario |

---

## La tesis técnica: Gerstner analítico, no FFT

Es la decisión de la que cuelga todo el proyecto, y las tres arquitecturas independientes llegaron a
ella por separado.

**El agua es una función pura de `(posición, tiempo, semilla, furia)`.** Se evalúa idénticamente en
CPU (física, red, IA, cámara, audio) y en el vertex shader. Suma de 8–16 olas de Gerstner.

Por qué **no** FFT como fuente de verdad, pese a ser lo más popular del ecosistema:

1. **Un espectro FFT no puede producir un tsunami.** Es estadísticamente *estacionario* por
   construcción: describe un mar en equilibrio con el viento. No existe valor de viento, fetch ni
   choppiness que genere un frente solitario dirigido. Quien adopte una base FFT creyendo que
   "subiendo el viento sale el tsunami" lo descubre en el mes 6. Ningún README lo advierte.
2. **Leer la GPU para la física mata el multijugador en silencio.** `texture_get_data()` es una parada
   síncrona (hay reportes de >4 ms para leer 4 bytes: el coste es el sync, no los datos), y la versión
   async tiene el [issue #105256](https://github.com/godotengine/godot/issues/105256) abierto desde
   abril 2025. Peor: cada cliente leería *su* textura de *su* GPU con *su* frameskip, así que las
   alturas divergen entre máquinas **sin ningún error ni warning**. El README de `tessarakkt/godot4-oceanfft`
   lleva desde el principio con "Multiplayer synchronization?" como TODO sin resolver.
3. **El sombreado plano tipo PEAK aplana el detalle de alta frecuencia** que la FFT genera. Pagaríamos
   compute shaders, cascadas y bugs abiertos para producir detalle que el shader va a borrar.

Lo que ganamos gratis: determinismo entre los 6 clientes replicando **una semilla, un reloj y un float**;
ancho de banda del océano **cero** en régimen permanente; el tsunami **autorable y telegrafiable** (al
ser función pura de `t`, cada cliente puede evaluarla en el futuro y saber al milisegundo cuándo llega);
y el preset gráfico BAJO juega **exactamente igual** que el ALTO.

La capa FFT queda como **capa visual opcional de fase 2**, que la física nunca consulta. Probablemente
nunca la activemos.

---

## Qué reutilizamos (todo verificado: URL, licencia y estado reales)

**Regla: vendorizar, nunca depender.** Copiar al repo con el commit hash anotado y auditar antes de
construir encima. Varias de estas bases son de una sola persona y con validación externa casi nula.

| Área | Base | Licencia | Qué nos da | Decisión |
|---|---|---|---|---|
| Arquitectura de API del océano | [Ocean3D-Org/ocean3d-lite](https://github.com/Ocean3D-Org/ocean3d-lite) | MIT | `get_height` / `get_displacement` / `get_surface_velocity`, inversión de Gerstner por punto fijo, `FloatingBody` multi-sonda con damping **relativo a la superficie móvil**, `storm_scale`, guard `steepness_sum() < 0.9`. Soporta 4.4–4.7 | **Vendorizar + auditar línea a línea** (5 scripts, `ocean.gd` son ~130 líneas; solo 2★, escrito con asistencia de IA) |
| Clipmap, LOD y snapping de cámara | [Chrisknyfe/boujie_water_shader](https://github.com/Chrisknyfe/boujie_water_shader) | MIT, 180★ | Generador de LOD por `SurfaceTool`, far plane al horizonte y **`CameraFollower3D` con snapping a rejilla** — el truco imprescindible que casi todos los tutoriales omiten y sin el cual los vértices "nadan" | **Portar el patrón.** Su shader es realista: se tira entero |
| Modelo de fuerzas de flotabilidad | [ManickYoj/godot-ocean-waves-buoyancy](https://github.com/ManickYoj/godot-ocean-waves-buoyancy) | MIT, 77★ | Celdas con **densidad independiente** y fuerza derivada del **volumen sumergido** (no muelles puntuales). Regala el hundimiento progresivo por inundación bajando un float por celda | **Canibalizar el modelo, reescribir la matemática** contra Jolt |
| Shader de agua estilizado | [Malidos/Stylized-Water-Shader](https://github.com/Malidos/Stylized-Water-Shader) | **CC0** | Absorción de color por profundidad contra el depth buffer y espuma de contacto. Licencia de dominio público: copiar sin obligaciones | **Canibalizar** |
| Rampa de luz toon | [eldskald/godot4-cel-shader](https://github.com/eldskald/godot4-cel-shader) | MIT, 301★ | Rampa de difusa por `GradientTexture1D` guardada como recurso + patrón de features conmutables. La rampa **global compartida** por agua, personajes y props es lo que hace que se lea como un mundo | **Canibalizar el patrón** |
| Outline | [dmlary/godot-stencil-based-outline-compositor-effect](https://github.com/dmlary/godot-stencil-based-outline-compositor-effect) | MIT, 61★, Godot 4.5+ | Outline por stencil solo en las mallas marcadas. **Única opción viable**: un outline global contornearía cada cresta del oleaje y produciría un hervidero de líneas parpadeantes | **Reutilizar** |
| Voz por proximidad | [goatchurchprime/two-voip-godot-4](https://github.com/goatchurchprime/two-voip-godot-4) | MIT, 177★, push 21-ago-2026 | Opus + RNNoise, 6 plataformas, demo corriendo en Godot 4.6 | **Reutilizar** |
| Template de integración de voz | [thegatesbrowser/godot-multiplayer](https://github.com/thegatesbrowser/godot-multiplayer) | MIT, 250★ | Voz posicional 3D sobre two-voip. ⚠️ **Su código ya no compila**: usa `AudioEffectOpusChunked`/`AudioStreamOpusChunked`, que two-voip borró en la v5.0 (28-may-2026, «Remove old chunking classes») | **Referencia conceptual, no copiar.** La idea (un `AudioStreamPlayer3D` anclado al jugador, con un `TwoVoipSpeaker` de hijo) son 15 minutos |
| Reloj de red | [foxssake/netfox](https://github.com/foxssake/netfox) → solo `NetworkTime` | MIT, 1074★ | Godot no trae reloj compartido ([proposal #6104](https://github.com/godotengine/godot-proposals/issues/6104) abierta desde 2023). **Ignorar `RollbackSynchronizer`** — el rollback re-simularía Jolt N veces por frame para cero beneficio | **Vendorizar parcialmente** |
| Transporte y lobby Steam | [GodotSteam (Codeberg)](https://codeberg.org/godotsteam/godotsteam) v4.22 (22-ago-2026) | MIT (el wrapper) + Steamworks SDK Access Agreement (el `.dll` de Valve) | Steam Datagram Relay: NAT traversal, oculta IPs, cero coste de servidor | **Reutilizar al final.** GDExtension para Godot 4.4+: se copia a `addons/`, no se recompila el motor. `SteamMultiplayerPeer` viene dentro desde la 4.17 (el repo `multiplayerpeer` aparte quedó fusionado: los tutoriales que mandan clonar dos repos están caducados). Se desarrolla con el **App ID 480** (Spacewar) sin pagar nada. ⚠️ El espejo de GitHub está **ARCHIVADO** y todos los tutoriales apuntan ahí. ⚠️ El mantenedor anunció (24-jun-2026) que quiere **restringir la licencia** «cerca de Godot 5»: al vendorizar, archivar copia literal del `LICENSE` con su SHA |
| Props de greybox | Kenney Nature Kit + Survival Kit | CC0 | Playtests honestos desde el día 1 (la gente juzga distinto un cubo que un barril) | **Reutilizar para validar**, no para publicar |

### Descartado, con motivo

- **`2Retr0/GodotOceanWaves`** (MIT, 3235★) — el mejor render de agua de Godot, pero es un *demo* sin
  LOD ni flotabilidad, semi-congelado (push abr-2025), con render roto en 4.4+ ([#11](https://github.com/2Retr0/GodotOceanWaves/issues/11)),
  ~10.000 errores de validación Vulkan/s ([#19](https://github.com/2Retr0/GodotOceanWaves/issues/19)) y
  dependencia de `imgui-godot` con assemblies C#. **La popularidad engaña.** Solo si algún día se
  activa la capa FFT, y como donante de GLSL.
- **`tessarakkt/godot4-oceanfft`** (MIT, 581★) — el único addon completo, pero su flotabilidad tiene
  **dos bugs verificados verbatim en el código**: multiplica una fuerza por `delta` antes de
  `apply_force()` (doble integración) y amortigua con `linear_velocity *= 1.0 - drag` (dependiente del
  tick rate). Su issue #10 *"Heavy buoyancy jitter"* lleva abierto desde 2024 y **empeora al subir el
  viento** — o sea, falla justo en tormenta. Copiar la arquitectura de nodos, jamás la matemática.
- **`Neo-DannyDeTour/GodotOceanWave`** — su propio autor lo declara obsoleto en la primera línea del
  README y usa readback **síncrono**, no asíncrono.
- **REBOOT16 Realistic Shoreline & Ocean Waves** (MIT+CC0, solver SWE Kurganov-Petrova real) — es la
  única implementación en Godot con shoaling, rotura y run-up emergentes. **Fuera de alcance** porque
  elegimos solo mar abierto. Reabrir únicamente si aparece costa jugable.
- **Flotabilidad nativa de Jolt** — **no existe en Godot**. Verificado por tres vías: no hay ficheros de
  buoyancy en `modules/jolt_physics/objects/`, la doc oficial *Using Jolt Physics* no la menciona ni una
  vez (ni en 4.6 ni en 4.7), y no hay ni una propuesta abierta pidiéndola. Se escribe a mano.
- **Balsa construible, malla de joints, rollback netcode, Terrain3D, late join, host migration** — todos
  descartados con motivo técnico documentado.

### Lista negra de licencias (a `THIRD_PARTY.md` desde el commit 1)

Sin licencia = todos los derechos reservados. **Leer para aprender, jamás copiar**:
`stvgale/Gerstner-Waves-Buoyancy` (`license = null` confirmado), `jdupuy/whitecaps`,
`CBerry22/Buoyancy-in-Godot-4`, `matthias-research/pages`.
**GPL (contaminante)**: Blender Ocean Modifier, Houdini Ocean Toolkit, Basilisk.
**No redistribuible**: Ocean3D versión completa (single-user), Crest, UE5 Water plugin, WaveWorks.
⚠️ Los **assets binarios** (`.obj`, skyboxes, `.wav`, texturas) de los repos MIT **no heredan la
licencia del código**: purgar antes de cualquier build pública. Ningún shader de godotshaders.com entra
sin verificar su licencia individual.

---

## Arquitectura, en escenas

Convención acordada: **cada sistema es una escena**, con `@tool` donde tenga sentido para previsualizar
en el editor, y todos los parámetros como `Resource` (`.tres`) editables sin tocar código.

```
nuevo-proyecto-de-juego/
├─ addons/ocean/
│  ├─ ocean.tscn / ocean.gd        # AUTOLOAD. Única fuente de verdad del agua.
│  ├─ wave_proxy.gd                # N olas Gerstner, k y fases CONGELADOS por semilla
│  ├─ spectrum_math.gd             # JONSWAP/TMA → amplitudes. Escala Douglas
│  ├─ ocean_events.gd              # Tsunami (onda N) y rogue waves (componentes dedicadas)
│  ├─ ocean_surface.tscn           # Clipmap: 1 parche + 6 anillos + snapping
│  ├─ shaders/ocean_surface.gdshader
│  ├─ shaders/ocean_waves.gdshaderinc   # ⚠️ MISMA fórmula que wave_proxy.gd
│  ├─ physics/floating_body.tscn        # RigidBody3D + sondas
│  ├─ physics/buoyancy_probe.tscn
│  └─ debug/ocean_debug.tscn            # HUD: Hs medido vs objetivo, jacobiano, slider de furia
├─ resources/sea_states/*.tres      # Perfiles de mar: calma, marejada, tormenta, tsunami
├─ game/
│  ├─ boat/fishing_boat.tscn        # UN RigidBody3D, N CollisionShape3D, N sondas
│  ├─ player/player.tscn            # CharacterBody3D + máquina de estados de nado
│  ├─ net/network_manager.tscn      # Abstrae ENet ↔ SteamMultiplayerPeer
│  └─ net/ocean_sync.gd             # Replica: semilla + reloj + furia + eventos
└─ THIRD_PARTY.md
```

### Contratos que no se rompen

- **`Ocean` (autoload) es la única puerta al agua.** Nadie consulta la altura por otro camino. Cero
  acceso a GPU desde la física.
- **Prohibido `Time.get_ticks_msec()` / `OS.get_ticks_msec()` dentro de `addons/ocean/`.** Arrancan en
  momentos distintos en cada máquina y producen océanos desfasados minutos. El océano solo lee
  `Ocean.sim_time`, un reloj **inyectado**: en single lo avanza el juego; en multijugador lo escribe el
  host desde `NetworkTime.time`. (El reloj inyectado es además lo que hace posibles los tests headless
  y el replay determinista.)
- **`ocean_waves.gdshaderinc` y `wave_proxy.gd` implementan la misma fórmula** y un test lo verifica.
  La deriva silenciosa entre ambos es el fallo más caro de esta arquitectura: los objetos flotarían
  medio metro por encima del agua visible y no se detecta hasta semanas después.
- **Los uniforms del shader se generan desde la MISMA tabla que usa la CPU** (`waves_for_shader()`).
  Nunca dos listas de constantes.
- **Semilla explícita** con un `RandomNumberGenerator` propio, nunca el RNG global.
- **Los jugadores se replican en espacio local del barco** (`barco_id` + transform local), nunca en
  espacio mundo. Cada máquina los compone contra su propia copia del barco. (Ver "El jugador sobre el
  barco", más abajo.)
- **El cliente evalúa el océano en el reloj de la interpolación, no en "ahora".** El shader y las
  consultas locales reciben `t − retardo_de_interpolación`. Gratis, porque el agua es función pura
  de `t`.

### Las cuatro reglas de la flotabilidad (contra Jolt)

Son la causa raíz de los bugs verificados en el ecosistema:

1. **Nunca** multiplicar la fuerza por `delta` antes de `apply_force()` — ya integra sobre el tick.
2. **Nunca** escalar `linear_velocity` a mano, **ni usar `linear_damp` como arrastre hidrodinámico** —
   `linear_damp` amortigua contra el mundo, que es exactamente lo que la regla 4 prohíbe. El arrastre
   es una **fuerza explícita por sonda** sobre la velocidad relativa a la superficie,
   `F = −c·(v_sonda − Ocean.get_surface_velocity())`, con **tope de estabilidad repartido entre las
   sondas del cuerpo**: la fuerza de un tick no puede invertir la velocidad relativa
   (`c_efectivo ≤ m/Δt`), o la sonda sobre-corrige y oscila — el mismo jitter del ecosistema por otra
   vía. `linear_damp` / `angular_damp` (con `DAMP_MODE_REPLACE`) quedan solo como estabilizador de
   base, bajo y constante.
3. **Clampar la profundidad** antes de convertirla en fuerza, o un cuerpo que cae desde una cresta de
   15 m sale disparado a la estratosfera (el "bug del barril cohete").
4. **Amortiguar contra la superficie móvil** (`v_sonda − Ocean.get_surface_velocity()`), no contra el
   mundo. Contra el mundo el objeto se resiste a subir con la ola y parece pegado; contra la superficie
   *cabalga* la ola, y de paso salen las corrientes gratis.

Más el **slamming force** (derivada de la profundidad por sonda; superado un umbral, impulso extra +
screen shake + partículas): son ~10 líneas y es lo que convierte "el barco sube y baja" en "el barco
**se estrella** contra el agua".

### El dial de furia 0–10

Una sola perilla mueve el mundo entero. **Interpolar en Hs (altura significativa), nunca en velocidad
de viento** — Hs escala ~U², así que interpolar U deja el dial muerto de 0 a 5 y explosivo de 8 a 10.
Escala Douglas: `[0, 0.1, 0.5, 1.25, 2.5, 4, 6, 9, 14, 18, 25] m`.

De `fury` cuelgan por `Curve` en un `.tres`: amplitud y steepness, choppiness, bias de espuma, tasa de
spray, densidad y color de niebla, LUT de color, energía del sol, camera shake, mezcla de audio,
probabilidad de rogue wave — y **la atenuación de la voz por proximidad**.

> **La mejor idea de diseño del proyecto, y cuesta cinco líneas:** en calma os oís a 30 m, en tormenta a
> 3. La comunicación se **degrada con el peligro**, exactamente cuando más la necesitáis. Convierte el
> estado del mar en una mecánica de comunicación y acopla el pilar del juego con el motor de comedia del
> género. El vigía tiene que gritar y aun así no le oyen; el equipo acaba inventando su propia jerga.

**Anti-popping:** los `k` y las fases de las olas se congelan por semilla al inicio de partida; al mover
el dial **solo se recalculan las amplitudes**. Si se remuestrearan los `k`, la física daría un salto
visible. Más un rate limit de ~0,4 unidades/s.

### El tsunami

El tsunami es una **onda N**: la cresta `A · sech²((d − c·(t − t0)) / W)` **precedida por una depresión
ancha y suave** (término negativo adelantado), sumada a la capa base tanto en el `.gdshader` como en el
`.gd`. Un sech² puro no contiene la retirada — el acto uno tiene que salir de la propia ecuación, no de
un script. Los tiers escalan en **tres dimensiones** (altura lineal, anchura ~√m, celeridad de onda
solitaria): escalar solo la amplitud da un acantilado vertical, no un tsunami más grande — y el tier
mayor viaja más rápido, así que el aviso se alarga en proporción (justicia). Replicación: **un RPC
fiable de ~50 bytes**, cero tráfico durante los 60 s de propagación.

Tres actos: **la retirada** (el nivel del mar baja 6 m, los sonidos se apagan — la flotabilidad y el
nado reaccionan solos, sin código nuevo: ésa es la prueba de que la arquitectura de capas funciona),
**el aviso** (línea blanca en el horizonte, subsónico creciente) y **el muro**.

⚠️ La cresta que rompe es una **malla low-poly animada a mano** con 4–8 huesos o blendshapes. Un
height field es *matemáticamente incapaz* de representar una cresta que se dobla sobre sí misma — toda
la industria lo resuelve así, y con estética plana es una ventaja: siluetas legibles y hitboxes
controlados por menos de 1 ms.

**Rogue waves** por focalización dispersiva (`φ_k = −k·x* + ω(k)·t*`) — que es literalmente cómo se
generan las olas monstruo en los tanques de olas reales — pero **jamás re-faseando las olas base**:
re-fasearlas en caliente teleporta la superficie entera del océano en un instante (la violación global
de la regla anti-popping, con patada de física a todo lo que flota), y además no da la talla: la cresta
de un foco perfecto es ≈ `√(N/8) · Hs`, así que con 8 olas da 1,0×Hs (menos que la mayor ola
estadística de una tormenta cualquiera) y con 16 roza la zona rogue solo si TODAS focalizan a la vez.
El evento instancia **2–4 componentes dedicadas** en `ocean_events.gd` — el mismo patrón que el
tsunami — con las fases de foco y la **amplitud rampeada 0→a→0** (~20–30 s): la rampa de amplitud no
popea, el mismo principio que el dial. Se replica con el mismo RPC fiable de ~50 bytes, y la altura del
monstruo se controla directamente con la amplitud del paquete en vez de rezarle a la estadística.
Escala objetivo: 2,2×Hs = rogue (la ola de Draupner), 3,0×Hs = monstruo (el techo exacto del breather
de Peregrine, cuyo factor de amplificación es 3).

### Estética PEAK

**El 70% del look no son shaders: es `WorldEnvironment`**, y sale en un día. La niebla hace tres
trabajos a la vez: da el estilo, esconde el LOD lejano (rendimiento) y es el instrumento dramático del
reloj de furia. Tres LUTs 3D (calma azul frío / tormenta verde-gris desaturado / tsunami casi
monocromo) interpolados por `fury`.

Agua **opaca** (nada de `hint_screen_texture`: fuerza una copia del back buffer sobre media pantalla y
es el coste dominante de cualquier océano en Forward+). Profundidad fingida con `DEPTH_TEXTURE`
cuantizada a 3–4 **bandas planas**. Facetado por `NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)))`.
**SDFGI, SSR y SSAO apagados el día 1** y no se vuelven a mirar.

**Espuma por jacobiano**, y aquí está el mejor retorno por línea de shader del proyecto: `J < 0` = la
cresta se pliega = rompe. El **mismo** criterio se evalúa analíticamente en CPU vía `Ocean.get_breaking()`,
y es lo que dispara el estado REVOLCADO, el daño y el VFX. **La espuma marca dónde te va a doler**:
feedback visual y mecánico salen del mismo número, así que el jugador siempre puede leer el mar.

> ⚠️ **Riesgo técnico nº1 del look:** el toon shading sobre olas **parpadea**. Cuantizar N·L con
> normales de alta frecuencia produce bandas que hierven al moverse, y ningún proyecto del ecosistema
> lo tiene resuelto porque todos son fotorrealistas. Mitigar en orden: alimentar el toon solo con las
> olas de baja frecuencia; `smoothstep` con ancho `fwidth(ndl)*1.5` en vez de `step`; roughness alto y
> constante; TAA. **Prototiparlo en F2, no en la fase de pulido.**

### Red

Autoridad en cuatro niveles, **sin predicción ni reconciliación**: movimiento del jugador
cliente-autoritativo; barco, carga y props host-autoritativos (los clientes **interpolan**, nunca
simulan); **al agarrar un objeto la autoridad se transfiere a ese cliente y vuelve al soltarlo** — es el
truco más rentable del netcode, porque elimina el lag de manipulación, que es donde vive toda la comedia
del género; daño, muerte y estado del mar host-autoritativos y fiables.

Desarrollar **todo con `ENetMultiplayerPeer` en localhost** detrás de `NetworkManager`, y cambiar a
Steam al final: es una línea.

#### El jugador sobre el barco — la costura crítica

El problema nº1 del género no es el agua ni el netcode por separado: es **una persona en primera
persona de pie sobre una cubierta que cabecea, a través de la red**. Ignorarlo produce tres fallos
concretos:

1. **Acarreo de plataforma.** `move_and_slide()` sobre un `RigidBody3D` que rota hereda mal la
   plataforma: la velocidad lineal más o menos, la rotación no — el barco gira bajo los pies y el
   personaje no gira con él, que en primera persona se siente como patinar. Ningún repo del ecosistema
   lo resuelve porque ninguno tiene personajes. Se acarrea **posición y yaw a mano por tick de física**.
2. **Dos relojes en el cliente.** El cliente interpola el barco ~100 ms en el pasado (buffer de
   snapshots), pero evaluaría el océano en el `t` actual. Con Hs 6 m y T 8 s la superficie se mueve a
   ~4,7 m/s: 100 ms de desfase = **hasta medio metro de error vertical** entre el barco replicado y el
   agua local — el síntoma exacto que el test de paridad existe para evitar, causado por el reloj y no
   por la fórmula.
3. **Jugadores fuera de la cubierta ajena.** El jugador cliente-autoritativo en espacio mundo se
   calcula contra *su* barco interpolado y se compone en las otras máquinas contra *otro* instante del
   barco: con mar gruesa, todos flotan ligeramente despegados de la cubierta en las pantallas ajenas.

**Una sola decisión resuelve los tres:** los jugadores se **simulan y replican en espacio local del
barco** (`barco_id` + transform local — lo que hace todo juego de barcos serio, Sea of Thieves
incluido), y el cliente **evalúa el océano en el reloj retrasado de la interpolación**: pasar
`t − retardo` al shader y a las consultas locales es gratis porque el agua es función pura de `t`.
Ambas cosas son contratos (arriba) y se diseñan **antes de escribir la primera línea de red**.

### Lenguaje: GDScript tipado

La evidencia dice que basta. El presupuesto estimado es ~200 sondas × 3 iteraciones × 8 olas ≈ 10k
evaluaciones trigonométricas por tick = **0,1–0,3 ms**, y el tipado estático genera opcodes que saltan
el unwrapping de Variant. **Pero es una estimación de sobremesa, no una medición**: F2 tiene un criterio
de aceptación duro (<2 ms con 200 sondas en la máquina objetivo). Si falla, se baja a C#/GDExtension
**solo el evaluador de altura**, no el proyecto entero. Nada de decidirlo por gusto.

---

## Fases

Cada fase termina en algo que se puede **abrir en el editor y jugar**. El orden está invertido respecto
a lo que propusieron las arquitecturas: **el gate de diversión va al principio**, no en la semana 6.

**F0 — Migración y andamiaje.** Migrar a Godot 4.7.2. Forzar `rendering/rendering_device/driver.windows = "vulkan"`
en desarrollo (y añadir QA en D3D12 a la checklist de release: es lo que verán los jugadores). `git init`.
`THIRD_PARTY.md` con la lista negra. Verificar que GodotSteam, two-voip y netfox abren limpios en 4.7.2
— es donde está el coste real de migrar, no en el motor. Fijar la GPU objetivo por escrito: **GTX 1060,
el mismo mínimo que PEAK**.

**F1 — El juguete (GATE DE DIVERSIÓN).** Tres olas seno sobre un plano, cuatro cápsulas jugables,
objetos que resbalan por una cubierta inclinada, **un agarre tonto** (un joint al agarrar, diez líneas,
sin transferencia de autoridad — la mitad de la comedia del género vive en manipular cosas), y un
quinto jugador con el slider haciendo de dios cabrón. **Con red mínima**: ENet replicando transforms de
cápsulas y el float del slider (~un día de trabajo que además es el esqueleto de F2) — el equipo es de
dos y los amigos están online; un gate cooperativo probado en solitario da falsos NO-GO (o falsos GO).
Y un prerequisito que no es pulido: **resolver el acarreo de plataforma antes de juzgar nada** — si
caminar sobre la cubierta se siente patinoso, el juguete parecerá aburrido por jank y no por concepto,
y se mata el proyecto por la razón equivocada. Sin arquitectura de más, sin arte. **Pregunta única:
¿os habéis reído sin que nadie os lo pidiera?** Si aquí nadie se ríe, se para y se rediseña — no se
sigue esperando que el arte lo arregle. Todo el proyecto es una apuesta sobre esta respuesta, y
descubrirla ahora cuesta días en vez de meses.

**F2 — "Algo flotando de verdad"** ← *el hito que pediste*. Vendorizar y auditar `ocean3d-lite`. Escribir
`wave_proxy.gd` + `ocean_waves.gdshaderinc` con paridad garantizada. Clipmap con snapping (patrón boujie).
Flotabilidad correcta contra Jolt con las cuatro reglas + slamming force. Dos ventanas en red con 20
cajas y un barco: **las cajas replicadas se asientan EXACTAMENTE sobre el agua que cada cliente evalúa
localmente** — que las posiciones coincidan entre pantallas es trivial por replicación y no prueba
nada; el test real cierra el lazo semilla→reloj→furia→render. Prototipar aquí el toon shading sobre
olas en movimiento. Criterios duros: caja-sobre-agua-local sin hueco ni clipping en el cliente,
flotabilidad <2 ms con 200 sondas (presupuesto del **host** — los clientes interpolan los props y solo
necesitan ~10 sondas para jugador local, cámara y audio), frame time estable en tormenta en la GTX 1060.

**F3 — El dial de furia.** `spectrum_math.gd`, perfiles de mar como `.tres`, rate limit, guard de
steepness, HUD de debug. Un slider que va de 0 a 10 en 25 segundos sin un solo salto. Test de estrés
automático que detecta el "barril cohete".

**F4 — La tripulación.** Personaje en primera persona, máquina de estados EN CUBIERTA → NADANDO → BAJO
EL AGUA → REVOLCADO. Agarre físico con transferencia de autoridad. Los cinco puestos del pesquero:
**timonel** (sujeta el timón, no puede soltar ni mirar atrás), **vigía** (el único que ve por encima del
oleaje), **achicador** (abajo, no ve nada, se ahoga lentamente), **amarrador** (si falla, se pierde la
carga), **rescatador** (el de la cuerda). Cero clases y cero bonus numéricos: **el juego no reparte
habilidades, reparte incomodidad**. Con 4 jugadores hay déficit de exactamente una mano, y ese déficit
*es* el diseño.

Tres reglas anti-frustración innegociables: el revolcón tiene duración **máxima fija** que se acorta al
forcejear, nunca indefinido; el oxígeno avisa mucho antes de ser letal; **un compañero siempre puede
sacarte**, convirtiendo el fallo individual en momento cooperativo. Y las corrientes se **suman** a tu
velocidad, nunca la sustituyen: si el input deja de producir efecto visible, se siente roto, no difícil.

**F5 — La voz y el mar.** two-voip sobre el cableado de thegatesbrowser. Atenuación y filtro paso-bajo
encadenados a `fury`. Oclusión mínima con un raycast por par hablante-oyente.
⚠️ **Presupuestar la cancelación de eco explícitamente**: no es que no esté terminada — **no está empezada** (el autor de two-voip abrió la incidencia con el texto literal «no tengo ni idea de cómo hacer esto» y la cerró como duplicada; PEAK, nuestra referencia, salió al mercado sin AEC). RNNoise es un *denoiser*, no un AEC, y
en un grupo de 4-6 la probabilidad de que alguien use altavoces es prácticamente 1 — un solo jugador
reinyectando audio arruina la mecánica que sostiene la mitad del valor del juego. VAD agresivo +
push-to-talk visible, y criterio de aceptación en el playtest.

**F6 — El tsunami.** Los tres actos, la malla animada de rompiente, el diseño de audio de la telegrafía
(el **silencio absoluto** de la retirada hace más trabajo dramático que el shader). Criterio: grabar 5
clips en un playtest y ver si alguno se comparte solo.

**F7 — La sesión.** Curva de furia automática sobre 25–35 min, carga que amarrar (`Generic6DOFJoint3D`
rígido con break force — Jolt **no soporta** joints blandos), muerte, el cadáver que flota boca arriba
con **voz intacta** y es el único que ve la ola llegar (el muerto pasa de espectador frustrado a sensor
táctico), hipotermia con brasero central, una silueta submarina. Primera run completa jugable por gente
ajena, sin explicaciones.

**F8 — Enviarlo.** Steam lobby, presets de calidad, accesibilidad (estabilización de horizonte y FOV
configurable **en el primer build público**, no en el parche 1.1), QA en ambos drivers, página de tienda.

### Lo que aún no tiene presupuesto y hay que abrirlo antes de F7

Las tres arquitecturas propuestas eran, en el fondo, planes de ingeniería de agua. **Entre las tres no
había una sola hora asignada a**: audio (que en un juego donde el mar es el antagonista es el 30-40% de
la experiencia), UI y flujo de lobby, guardado de settings, onboarding (en un coop de compra por impulso,
los primeros 90 segundos deciden el reembolso), pipeline de arte propio, animación de personaje,
localización, telemetría de playtest, herramientas de replay determinista para depurar desincronizaciones,
y **rejugabilidad** — si lo único que cambia entre runs es la semilla del oleaje, el mar se ve igual en la
run 1 y en la 20.

---

## Riesgos

| Riesgo | Severidad | Mitigación |
|---|---|---|
| **El juguete sale plano**: estar de pie sobre algo que se mueve es interesante 90 s y luego solo molesto | **CRÍTICA** | Por eso F1 es un gate GO/NO-GO al principio. Palancas de rediseño en orden: subir amplitud (es un float), bajar fricción de cubierta, añadir carga pesada deslizante. La arquitectura de capas hace que ningún pivote tire el trabajo técnico |
| **SHORE** ([Steam 4280880](https://store.steampowered.com/app/4280880/), Unity, un dev, Q4 2026) ya vende *"fight storms, tsunamis... your raft is fully physics-based"* | **ALTA** | Diferenciación desde el día 1: ellos son balsa / viaje / exploración / 1-4 / family friendly. Nosotros somos **tripulación de pesquero**, runs cortas, 2-6, horror-comedia y **la ola como jefe final**. El titular no es "coop de balsa con olas", es **"PEAK pero la montaña viene hacia ti"** |
| El toon shading sobre olas parpadea | **ALTA** | Prototipar en F2 con tiempo explícito, no tratarlo como pulido |
| Deriva silenciosa entre `.gdshader` y `.gd` | **ALTA** | Golden vectors en CI desde F2 + generar uniforms desde la misma tabla |
| Determinismo roto por un detalle tonto (RNG global, `Time.get_ticks_msec()`) | MEDIA | Prohibición por convención + grep en CI. El síntoma es traicionero: el océano se ve perfecto en cada pantalla por separado |
| Rendimiento en GPU integrada — el jugador con portátil malo arrastra al grupo entero | MEDIA | GTX 1060 como objetivo desde F2, perfilar ahí y no en la máquina de desarrollo. Ventaja estructural: como la física vive en CPU e ignora el render, **todo downgrade gráfico es gratis** y no altera el gameplay ni el determinismo. Y el presupuesto de sondas es del host: que el portátil malo no haga de host |
| Bases vendorizadas frágiles (ocean3d-lite tiene 2★ y un commit) | MEDIA | Vendorizar con commit hash y auditar. Lo que tomamos prestado es la **arquitectura y el trabajo aburrido**, no algoritmos difíciles: la suma Gerstner son ~30 líneas reescribibles |
| El agarre físico sobre suelo móvil pasa de gracioso a injusto | MEDIA | El jugador debe poder **anticipar** el balanceo (sonido, horizonte, espuma) y **siempre** debe existir una acción de recuperación. Si no podía hacer nada, no es comedia: es castigo |
| La moda del friendslop caduca | MEDIA | Planificar para un pico corto: sin progresión persistente que mantener, precio de impulso, lanzamiento rápido |

---

## Verificación

**En cada commit (CI, `godot --headless --script`):**
- **Paridad por golden vectors.** En headless **no existe `RenderingDevice`** (verificado:
  [godot-proposals #8661](https://github.com/godotengine/godot-proposals/discussions/8661),
  [PR #98247](https://github.com/godotengine/godot/pull/98247)), así que el shader no puede ejecutarse
  en CI. El seguro de vida se parte en dos: (a) en una máquina con GPU, un **tool de editor** genera la
  tabla golden `(pos, t, semilla, furia) → h_gpu` de 1000+ puntos × 32 instantes y se commitea —
  **regenerarla es obligatorio en todo commit que toque una fórmula del agua**; (b) CI compara la CPU
  contra la tabla y falla si `max|h_cpu − h_golden| > 1e-3 m` — corre headless en cualquier parte.
  Cuesta dos días y evita semanas de depuración visual.
- **Grep de `Time.get_ticks_msec`** en `addons/ocean/` → build rojo.
- **Barrido automático de furia 0→10** con 6 cuerpos y 40 props: falla si alguna velocidad supera el
  umbral del "barril cohete".

**Manual, por fase:**
- **Test GPU real de paridad** (tool de editor, máquina con GPU): regenerar los goldens y comprobar en
  vivo con las esferas de `parity_markers.gd` (puntos calculados en CPU clavados sobre el mar que
  dibuja la GPU: si se despegan, hay deriva). Es la mitad del seguro de vida que la CI no puede correr.
- **Dos ventanas del editor en red**: no comparar solo posiciones lado a lado — idénticas por
  construcción, porque el cliente interpola lo que manda el host. Comprobar que **cada caja replicada
  se asienta sobre el agua evaluada LOCALMENTE por ese cliente**. Es la única forma de cazar la
  divergencia, porque cada pantalla por separado se ve perfecta.
- **HUD de debug** (`addons/ocean/debug/ocean_debug.tscn`): Hs objetivo vs medido, jacobiano, ms de CPU y
  GPU del agua, slider con teletransporte a los presets 0/3/5/8/10.
- **Perfilado en la GTX 1060**, nunca en la máquina de desarrollo, y en la escena real — todas las cifras
  publicadas del ecosistema son de escenas vacías.
- **Playtest con latencia simulada** 80-150 ms y 2-5% de pérdida (netfox lo trae con un toggle).
- **QA en D3D12 y Vulkan** antes de cualquier build pública.
