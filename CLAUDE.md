# Proyecto Agua — guía para trabajar en este repo

Cooperativo de supervivencia para 2-6 amigos: tripulación de un pesquero en un mar
que escala de la calma social al tsunami. **El agua es el antagonista.** La tesis
completa está en `docs/DISENO.md`; las decisiones y su porqué en `docs/DECISIONES.md`.

**La tesis técnica que sostiene todo:** el océano es una función PURA de
(posición, tiempo, semilla, furia) — olas Gerstner + eventos analíticos (onda N) —
evaluada idéntica en CPU y en el vertex shader. Por eso la telegrafía nunca miente
(se puede consultar el futuro), 6 clientes coinciden replicando ~50 bytes, y la
dificultad jamás se ajusta a escondidas.

## Ejecutar y probar

⚠️ **El `godot` del PATH es 4.6.1 — NO usarlo.** El proyecto va con **Godot 4.7.2**:

```
C:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe
```

Correr `--import` con el 4.6.1 viejo **corrompe en silencio** los `.import` de todo
el proyecto (borra claves que solo conoce 4.7.2, exit 0, sin ningún error — el daño
solo se ve en `git status`). Tras cualquier `--import`, comprobar
`git status -- '*.import'` y `git checkout --` lo que no sea el asset agregado.

- Jugar: abrir el proyecto en el editor (arranca en el **menú principal**,
  `game/ui/menu/menu_principal.tscn` — es el `run/main_scene` desde el
  24-ago-2026; ver `docs/MENU.md`), o saltárselo yendo directo al mundo con
  `--path . game/world/toybox.tscn` (juguete F1) / `game/world/tsunami.tscn`
  (secuencia dirigida con actos), que sigue siendo el ciclo de trabajo normal.
- **El HUD de debug se abre y se cierra con `Ñ`** (o con esa MISMA posición de tecla,
  el `;` de un QWERTY US). Nace cerrado desde el 24-ago-2026, y cerrado no responde
  ninguno de sus atajos (`1/2/3` tsunami, `0` limpiar, `N` +3 h, `C` caña, `T` trueno,
  `R` rayo, `P` parte, `B` reflotar): tenerlos sueltos sobre el juego era tener `B` y
  `P` a un dedo de distancia en mitad de una partida. Ver `docs/DECISIONES.md`.
- Tests (headless, salen con código ≠ 0 si algo falla — correr TODOS tras cada cambio):

```
<godot> --headless --path . tests/f1_tests.tscn
<godot> --headless --path . tests/tsunami_tests.tscn
<godot> --headless --path . tests/fishing_tests.tscn
<godot> --headless --path . tests/day_night_tests.tscn
<godot> --headless --path . tests/hud_launcher_tests.tscn
<godot> --headless --path . tests/music_tests.tscn
<godot> --headless --path . tests/boat_asset_tests.tscn
<godot> --headless --path . tests/weather_tests.tscn
<godot> --headless --path . tests/parte_tests.tscn
<godot> --headless --path . tests/parity_tests.tscn
<godot> --headless --path . tests/typography_tests.tscn
<godot> --headless --path . tests/farol_tests.tscn
<godot> --headless --path . tests/porteo_tests.tscn
<godot> --headless --path . tests/net_tests.tscn
<godot> --headless --path . tests/anim_tests.tscn
<godot> --headless --path . tests/player_face_animator_tests.tscn
<godot> --headless --path . tests/rig_tests.tscn
<godot> --headless --path . tests/fish_asset_tests.tscn
<godot> --headless --path . tests/bodega_tests.tscn
<godot> --headless --path . tests/manual_pump_tests.tscn
<godot> --headless --path . tests/agua_tests.tscn
<godot> --headless --path . tests/bomba_tests.tscn
<godot> --headless --path . tests/volcado_tests.tscn
<godot> --headless --path . tests/gobierno_tests.tscn
<godot> --headless --path . tests/voz_tests.tscn
<godot> --headless --path . tests/microfono_tests.tscn
<godot> --headless --path . tests/menu_tests.tscn
<godot> --headless --path . tests/partida_tests.tscn
<godot> --headless --path . tests/perf_tests.tscn
```

⚠️ Esta lista tiene que llevar **TODOS** los arneses de `tests/`. Llegó a
listar 12 cuando en disco había 17: cinco arneses que nadie corría, porque
"correr todos los tests" significa en la práctica "correr los que están
aquí". Un arnés nuevo entra en esta lista **en el mismo commit** que lo crea.

- ⚠️ `perf_tests` es el ÚNICO arnés que no comprueba corrección sino **coste**: mide
  la flotabilidad contra el presupuesto de F2 (<2 ms con 200 sondas). **Hoy sale en
  rojo a propósito** — el criterio no se cumple (~4,7 ms de mediana en build debug,
  ~2,9 ms incluso en el mínimo). No está roto: es la medición que F2 pedía y que
  hasta ahora nadie había hecho. La lectura y las palancas las imprime él mismo.
- `tests/capture_manguera_perf.tscn` mide el coste de la manguera de la bomba, y
  se corre CON `--headless`. Nació de una caída a 7 fps: la manguera se
  redibujaba entera 120 veces por segundo (medio segundo de CPU por segundo de
  juego) aunque nadie la tocara. Dibujar es presentación y va en `_process`,
  nunca en el tick de física.
- `tests/capture_agua_cubierta.tscn` saca los tres momentos que el jugador tiene
  que leer del agua de cubierta (charco / rodilla=alarma / cintura=naufragio).
  Necesita ventana: `<godot> --path . tests/capture_agua_cubierta.tscn`. Los tests
  garantizan los numeros; que un charco SE VEA charco solo se puede mirar — de
  hecho asi se cazaron dos fallos que la suite daba por buenos (el agua asomando
  por fuera de la amura y media cubierta seca por un filtro mal puesto).
- Los `tests/capture_*.tscn` no son tests: generan capturas o informes para revisar.
  `capture_perf` mide el frame time (p50/p95/p99 y peor frame) en tormenta furia 7-9;
  necesita ventana y GPU, así que **no se corre con `--headless`**:
  `<godot> --path . tests/capture_perf.tscn -- --perf-out=<archivo> [--perf-res=1920x1080]`.
- **Paridad CPU/GPU: SÍ hay test automático** (`tests/parity_tests.tscn`, 24-ago-2026).
  Va en dos mitades porque en headless no existe `RenderingDevice`:
  1. `addons/ocean/debug/golden_gen.tscn` corre **con ventana y GPU**, le pregunta al
     shader de verdad (vía `golden_probe.gdshader`, que incluye el mismo
     `ocean_waves.gdshaderinc`) el valor en 1024 puntos × 8 instantes × 3 furias ×
     2 semillas, y guarda `tests/golden/ocean_golden.res`.
  2. `tests/parity_tests.tscn` corre **headless** y compara la CPU contra esa tabla;
     falla si algo se aparta más de 1 mm. Medido hoy: peor 0,5 mm, y ese peor caso
     está en `t = 941,7 s`, o sea que es la precisión de 32 bits de la GPU
     acumulando fase — no una divergencia de fórmula.
  ⚠️ **Regenerar la tabla es OBLIGATORIO en todo commit que toque una fórmula del
  agua**, y va en el mismo commit. Si no, el test compara CPU nueva contra GPU vieja.
  El comprobador VISUAL (`parity_markers.gd`, esferas de CPU sobre el mar de la GPU)
  sigue existiendo y sirve para ver DÓNDE se despega, no para saber si se despegó.

## Mapa

```
addons/godotsteam/     GodotSteam 4.22 (GDExtension, MIT). SOLO win64 y con el
                       manifiesto RECORTADO a mano — ver THIRD_PARTY.md. Carga en
                       4.7.2 y trae `SteamMultiplayerPeer`, pero todavía no se usa:
                       el transporte por defecto sigue siendo ENet.
addons/ocean/          El agua. Autoload `Ocean` = LA ÚNICA puerta de consulta.
  wave_proxy.gd        Campo Gerstner (JONSWAP). Espejo exacto del shader.
  ocean_events.gd      Tsunamis (onda N con retirada). Espejo exacto del shader.
  tsunami_tier.gd      Resource: MURO/COLOSO/LEVIATÁN escalan alto+ancho+rápido.
  shaders/             ocean_waves.gdshaderinc = la MISMA matemática que la CPU.
  clima/               El PARTE METEOROLÓGICO: `ParteMeteorologico` (el guion del
                       clima como curvas consultables en cualquier t) y
                       `GeneradorParte` (quien lo redacta desde la semilla, y
                       quien hace cumplir «si sube la lluvia sube la furia»).
  physics/             FloatingBody3D + BuoyancyProbe3D (celdas, inundación) +
                       AdrizamientoModel (el barco vuelve solo del revés).
  debug/               HUD de furia/lanzador de tsunamis + esferas de paridad.
game/
  world/               toybox.tscn (F1), tsunami.tscn, día/noche, TsunamiDirector.
  boat/                fishing_boat.tscn (celdas de flotación), barrel.tscn,
                       bodega.tscn (estiba física en el socket HoldAft).
  player/              Player (cubierta/nado) + CameraFeedback (anti-mareo) +
                       Portador (porteo: manos, prompt, lanzar — docs/PORTEO.md).
                       El modelo activo es `game/player/pescador_smooth.glb`.
  props/               Portable3D (la base de todo lo portable), farol.tscn +
                       gancho_farol.tscn (docs/FAROL.md), roles-objeto (radio,
                       llave del motor, caja, bichero) y soporte_cania.tscn
                       (la caña clavada pesca sola). Y cubo_cebo.tscn: el balde
                       de duelas con su cebo (`models/bait_bucket.glb`, fuente
                       en tools/build_bait_bucket.py) — el nivel se dibuja
                       escalando la masa y posando el copete, con el calibre
                       del interior leído del propio GLB. Ver docs/PESCA.md §5.
  net/                 Autoload `Net` (ENet localhost, F9 = host / F10 = unirse;
                       `Net.Transporte` es la puerta ENET/STEAM y ENET es el
                       defecto A PROPOSITO: Steam es una sesion por PC y se
                       llevaria por delante el ciclo de dos ventanas y el
                       loopback de `net_tests`)
                       + cuatro clases PURAS y testeables, que es donde vive todo
                       lo que decide algo: NetMath (transformadas, reloj, códec
                       del lote), NetPorteo (el árbitro del agarre y las tablas
                       de identidad), NetLag (latencia simulada) y NetTripulacion
                       (la lista de TAB: nombres saneados, orden estable y el
                       retardo que solo el host puede medir). Ver docs/RED.md.
                       ⚠️ `Net` es un autoload SINGLETON: no se pueden levantar
                       host y cliente en un proceso, así que un RPC no se puede
                       testear — por eso los cuerpos de los RPC son envoltorios.
  fishing/             La caña: FightModel (matemática testeable), rod, HUD, peces,
                       tiers de pez y de caña (RodTier; ver docs/PESCA.md).
  audio/               Autoload `SfxLibrary` (SFX de pesca: síntesis en vivo, más
                       el latigazo horneado en `fishing/`) +
                       `MusicDirector` (cama musical). El audio NO es procedural
                       por defecto: se genera con ElevenLabs (ver política abajo).
                       La VOZ, en dos mitades independientes: `VozModel` +
                       `VozProximidad` (a qué distancia te oyen, según el ruido
                       del mar) y el autoload `Microfono` (qué aparato escucha y
                       con cuánta ganancia, 0-200 %). Ninguna necesita Steam.
  ui/                  `GameTypography`: LA ÚNICA fábrica de fuentes (regla 11).
                       PorteoHud: el prompt del porteo y la barra de lanzar.
                       Autoload `Partida` (`partida.gd`): la sesión vista desde
                       dentro — el menú de `Esc` (Continuar / Volver al menú /
                       Salir) y la lista de tripulación de `TAB` con sus pings.
                       Es autoload para que la tengan TODAS las escenas
                       jugables sin acordarse de instanciarla, y `Esc` NO pausa
                       nada (en coop no se puede, y el HUD de debug tiene que
                       seguir alcanzable con el ratón suelto).
    menu/              El MENÚ PRINCIPAL (`run/main_scene`), con el mar de día
                       de fondo: `MenuPrincipal` (la pantalla) + cuatro clases
                       puras — `MenuNavegacion` (la pila de paneles),
                       `ControlesBasicos` (la ayuda de teclas leída del
                       InputMap, que así no puede mentir), `MenuAjustes` (lo
                       que se recuerda en `user://ajustes.cfg`) y `EstiloMenu`
                       (la paleta y las cajas, compartidas con el menú de Esc:
                       la regla 11 aplicada al color) — más `CamaraMenu`.
                       Ver `docs/MENU.md`.
assets/fonts/          Las tres voces vendorizadas + su OFL (Anybody, Atkinson
                       Hyperlegible, Noto Sans Symbols).
resources/             Balance editable: tiers de tsunami y de caña, cebos,
                       perfil día/noche (.tres).
tests/                 Arneses headless por sistema + capture_* (capturas).
docs/                  DISENO.md (diseño), DECISIONES.md (cerradas y abiertas),
                       CLIMA.md (lluvia/truenos/viento: principios y plan por fases),
                       PESCA.md (tiers de pez/caña y el plan «más peces, más rápido»),
                       PORTEO.md (manos + cinturón chico: el "inventario" del juego),
                       RED.md (la costura jugador↔barco↔mar y las fases R0-R2),
                       CHIGRE.md (la red DE PESCAR, de a 2 — diseño, sin código),
                       FAROL.md (la luz portátil y sus cinco decisiones),
                       TIPOGRAFIA.md (la voz "Faena costera" y sus reglas de uso),
                       MENU.md (el menú principal: los tres modos, el mar de
                       fondo y el orden de operaciones que exige la red).
THIRD_PARTY.md         Licencias. Se actualiza EN EL MISMO COMMIT que la dependencia.
```

## Las reglas que no se rompen

1. **Todo el mundo pregunta el agua a `Ocean` y solo a `Ocean`.** Nadie lee la GPU
   (`texture_get_data` desincroniza clientes en silencio), nadie duplica fórmulas.
2. **En `addons/ocean/` está prohibido `Time.get_ticks_msec()`/`OS.get_ticks_msec()`.**
   Solo `Ocean.sim_time` alimenta al océano; en multijugador lo escribirá el host.
   (En `game/` sí se usa `Time` para efectos visuales locales — eso es presentación.)
3. **CPU y shader son espejos.** Si tocas una fórmula en `wave_proxy.gd` u
   `ocean_events.gd`, tócala también en `ocean_waves.gdshaderinc` (y al revés), y
   comprueba con las esferas de paridad. La deriva es COMPLETAMENTE silenciosa.
4. **Determinismo = semilla explícita.** Nada de RNG global en lógica de juego que
   deba coincidir entre máquinas. El RNG global solo para presentación (variación
   de audio, feel) que puede divergir sin que pase nada.
5. **Flotabilidad (las 5 reglas de `FloatingBody3D`):** no multiplicar fuerzas por
   delta; no `velocity *= (1-drag)` (se usa `linear_damp` + `DAMP_MODE_REPLACE`);
   clampar la profundidad antes de convertirla en fuerza (el "barril cohete");
   amortiguar contra la SUPERFICIE MÓVIL, no contra el mundo; y medir los brazos
   desde el CENTRO DE MASAS, no desde el origen del nodo (`constant_torque` se
   aplica respecto al centro de masas, así que medirlos desde el origen tumba el
   cuerpo en vez de adrizarlo — el lastre del barco no hacía nada). Más el tope
   de estabilidad del drag repartido entre sondas — no lo quites, explota en
   tier 3.
6. **Las corrientes se SUMAN al input del jugador, nunca lo sustituyen.** Si el
   input deja de producir efecto visible, el juego se siente roto, no difícil.
7. **Cámara anti-mareo:** CERO rotación añadida por código. Shake solo traslacional
   (≤2.5 cm, trauma²), FOV kick con tope ±5°, y todo cuelga de `effects_enabled`.
   Es deliberado (primera persona sobre un barco que YA rota) — no lo "corrijas".
8. **El feedback jamás miente.** Todos los canales (chirrido, sedal, HUD, rumble)
   leen la MISMA tensión real. Y todo fallo se telegrafía ANTES de castigar:
   "me avisó", nunca "me robó".
9. **Licencias:** juego comercial (Steam). Nada entra sin licencia verificada y
   anotada en `THIRD_PARTY.md` en el mismo commit. Vendorizar, nunca depender.
10. **Audio: por defecto, NO procedural — se genera con ElevenLabs.** La música
    (`MusicDirector`) ya sigue esta política, y el latigazo del lanzamiento
    (`SfxLibrary.cast_whip`, en `game/audio/fishing/`) es el primer SFX horneado
    que entra por ella. Excepción conocida, no un patrón a imitar: el RESTO de
    `SfxLibrary` (los SFX de pesca) sigue siendo síntesis en vivo, de antes de
    fijar la regla; el clima (`docs/CLIMA.md`) usa recetas proceduralmente
    generadas pero horneadas a `.wav`, otra excepción anterior. Todo audio de
    ElevenLabs lleva su fila en `THIRD_PARTY.md` (origen, fecha, licencia — y el
    aviso de que la licencia tiene que sobrevivir a la baja del plan).
11. **Tipografía: el texto pide sus fuentes a `GameTypography` y solo a él.**
    Ninguna pantalla fija una fuente, un peso o un ancho por su cuenta (nada de
    `wdth`/`wght` sueltos en un `.tscn`): si `¡RECOGE!`, `MURO` y el título futuro
    no salen de la misma fábrica dejan de ser la misma familia. La dirección es
    **"Faena costera"** (`docs/TIPOGRAFIA.md`): Anybody condensada para
    imperativos, resultados y actos —en MAYÚSCULAS—; Atkinson Hyperlegible para
    teclas, números, unidades, ayuda y texto sostenido —en frase normal—; Noto
    Sans Symbols vendorizada SOLO como reserva de flechas (una instrucción no
    puede cambiar de forma según la fuente instalada en cada SO). El ancho
    **nunca se anima con la furia**: mover las métricas de lo que el jugador
    está leyendo es adorno, no feedback (regla 8). Sobre el mundo 3D se mantiene
    contorno oscuro + sombra corta — la fuente no sustituye al contraste contra
    espuma o noche —, y el color expresa estado, jamás una instrucción por sí
    solo. Las tres fuentes van vendorizadas con su OFL (regla 9) y
    `tests/typography_tests.tscn` protege ejes, cobertura de glifos y cableado
    del HUD. Excepción conocida: el HUD de debug del océano sigue con la fuente
    técnica de Godot (columnas alineadas con espacios manuales, no es UI final).
12. **Modelo activo del pescador: se usa `game/player/pescador_smooth.glb` y
    ningún otro modelo.** `game/player/player.tscn` es la escena que lo instancia.
    La fuente editable es `source_assets/player/pescador_smooth.blend` y el
    generador reproducible es `tools/build_pescador_smooth.py`; todo cambio
    visual debe hacerse desde esa fuente y regenerar el Blend/GLB juntos. El
    `game/player/pescador.glb` histórico queda sólo como referencia/rollback y
    no se debe volver a conectar a escenas nuevas.

## Parametrización — dónde vive cada número

- **Invariante físico/matemático** (límite de rotura, steepness, profundidad
  efectiva…) → `const` en el archivo que lo usa, con comentario del PORQUÉ.
- **Knob de feel o de secuencia por instancia** (velocidades, umbrales de acto,
  ángulo de agarre…) → `@export` con comentario, agrupado con `@export_group`.
- **Balance que edita diseño sin tocar código** (tiers de tsunami, perfil
  día/noche) → `Resource` + `.tres` en `resources/`.
- **Nunca el mismo número en dos sitios.** Los uniforms del shader se empaquetan
  desde la MISMA tabla que usa la CPU (`Ocean.apply_to_material`).
- La tabla de especies vive en `fish_species.gd` como const; si crece o diseño
  necesita editarla, pasarla a `.tres` como los tiers.

## Convenciones

- **GDScript tipado** — el warning `untyped_declaration` está activo y se respeta.
- Comentarios y docstrings **en español**, y explican el **porqué** (la física, la
  decisión de diseño, el bug que evitan), no el qué. Todo archivo nuevo lleva su
  bloque `##` de cabecera contando qué papel juega. Es la práctica más valiosa del
  repo: mantenla.
- Commits **en español, pequeños y con intención** ("El tira-y-afloja: la lucha ya
  es un minijuego"), no "fix" ni "wip". Documentación de una decisión → mismo commit.
- Cada fallo SILENCIOSO descubierto (determinismo, paridad, cableado de escenas)
  se convierte en test headless. Los ruidosos ya avisan solos.
- El HUD de debug del océano es sagrado en F1: la perilla de furia en manos de
  alguien haciendo de dios ES la herramienta de validación del juego.

## Estado (2026-08-23)

- **Hecho (F1 y algo más):** océano determinista + flotabilidad Jolt + toybox;
  modo tsunami con 3 tiers escalando; lanzador en HUD debug; ciclo día/noche
  determinista; la caña completa (picada por capas, lucha tira-y-afloja, SFX
  procedural, UI de pesca, anti-mareo); cama musical (`MusicDirector`, ElevenLabs);
  sistema tipográfico "Faena costera" (`GameTypography`, HUD de pesca y señal
  de la boya, fuentes vendorizadas);
  investigación de clima entregada (`docs/CLIMA.md`) con audio de lluvia/truenos
  ya en `game/audio/weather/`; documento de diseño; clima fase A (lluvia y viento
  en `Ocean` + shader — rachas puras por suma de senos, cat's paws, estrías,
  gotas visibles con `RainParticles3D`; la lluvia es INDEPENDIENTE de la furia
  (`Ocean.rain_level`, decisión de diseño); modo lluvia y horario en el HUD
  debug; `tests/capture_weather.tscn` para revisar el look); tiers de pesca
  (ventana de rotura por tier de pez — fix del «rompe demasiado rápido» —,
  legendaria Aguja azul, escalera de 3 cañas `RodTier` con tecla C en el HUD
  debug; diseño y roadmap «más peces, más rápido» en `docs/PESCA.md`);
  el farol de tormenta con sus ganchos (`docs/FAROL.md`); porteo fases A y B
  (`Portable3D` + `Portador` + bodega física + lanzar con carga + prompt;
  cinturón de 2 huecos con Q, radio y llave del motor —que se hunde—, caja y
  bichero, soporte de borda donde la caña clavada PESCA SOLA, y la caña se
  guarda del viewmodel al portear — decisión «manos + cinturón chico» en
  DECISIONES; `docs/PORTEO.md`); clima fase B parcial (autoload `WeatherAudio`:
  camas por rain01/viento con fase en sim_time, LPF de cabina contra el volumen
  del refugio, truenos por distancia con tecla T; cortina de lluvia lejana
  `RainCurtain3D`; quedan splashes, spray de slam, banderas y empuje de viento —
  estos dos últimos esperan a que aterrice el rework de barco/rig); red R0+R1
  (autoload `Net`: ENet localhost con F9/F10, mismo mar por semilla+reloj+furia,
  barco y props host-autoritativos, porteo completo con arbitraje y agarre
  pesimista, el pez lo pare el host pero la especie la decide quien pescó,
  eventos del océano con `t0` explícito, HUD de debug reenviado al host y
  latencia simulada `--net-lag=120,30,2` — ver `docs/RED.md`).
- **Agua embarcada y achique (24-ago-2026):** el barco se inunda y se puede
  hundir, y la bomba lo achica. `AguaEmbarcada` (host-only, hijo del barco) mete
  agua por mar gruesa —vía barlovento—, lluvia, olas sobre la borda y celdas
  enterradas; el agua no es masa, es empuje que se le quita al casco.
  ⚠️ Desde el 24-ago el agua **NO INCLINA**: la fuerza usa la inundación MEDIA
  (`sesgo_escora` = 0), así que el barco se hunde RECTO. La escora estorbaba al
  feel y sobre todo era ILEGIBLE — era el único aviso de dónde estaba el agua, así
  que el sistema quedaba mudo. El aviso pasa a ser VER el agua en cubierta (paso 2
  del rediseño). Y quitarla destapó que `flood_probe` TIRABA el agua que no cabía
  en una celda: la mar gruesa entra siempre por barlovento, esas celdas saturaban
  y se perdía el 41 % del agua de la tormenta (0,0116/s medidos contra 0,0198/s
  prometidos). Ahora rebosa a las demás. Ver DECISIONES.
  Umbrales calculados en frío (alarma 0,55, naufragio 0,85
  sostenido 3 s) y reserva de flotabilidad subida a ×6 el peso para que el
  naufragio se pueda leer y avisar. La bomba achica LA CELDA del cabezal —elegir
  cuál es la decisión—, al 50 % en solitario y al 100 % con alguien dirigiendo la
  manguera, sin candados: sale de la cuenta de manos. `B` en el HUD de debug
  reflota. Réplica a 4 Hz (`NetAgua`, 8 celdas en un byte cada una). Balance en
  `resources/agua/agua_embarcada.tres` — entrada y salida en el MISMO recurso,
  porque el punto de equilibrio es el dial de dificultad. Ver
  `docs/DECISIONES.md` §Agua embarcada y `docs/BOMBA_MANUAL.md`.
  La bomba es un CICLO DE DOS TIEMPOS: mantener el clic chupa de la celda a una
  cámara y soltarlo la escupe al mar, así que apretar sin soltar deja de ser
  óptimo. El agua de la cámara sigue contando a bordo hasta que se escupe —si no,
  chupar y no escupir nunca burlaría el umbral de naufragio—, y de ahí sale que
  chupar corrija la escora y escupir baje el nivel. **La estación ya se replica**
  (24-ago-2026): los seis verbos van por el patrón del porteo — `Net.pedir_bomba`
  → el host arbitra con `BombaModel.arbitrar` → `_aplicar_bomba` a todos —, con
  agarre pesimista, el motivo del rechazo dicho por su nombre, la palanca
  mandando **flancos** y no muestreo (dos eventos por segundo, no sesenta RPC), y
  el host sacando de la estación a quien se desconecta, que si no la bomba queda
  ocupada por un fantasma y nadie puede achicar. Identidad en `BombaModel.BOMBAS`,
  APPEND-ONLY por índice: la segunda bomba entra AL FINAL. Con esto el 50 %/100 %
  de DISENO por fin se puede JUGAR: uno en la palanca y otro dirigiendo el
  cabezal. Lo único host-only que queda es `carga_camara` (≤3 % de divergencia en
  el nivel de un invitado, invisible y documentada).
  Pendiente: el FEEL de la bomba (banda de cadencia, cavitación, la pesa animada,
  audio) y los agujeros por daño.
- **El vuelco (24-ago-2026):** el barco ya no se queda boca abajo. Las ocho
  celdas están en un plano, así que el casco flota igual del derecho que del
  revés (medido: soltado a 80° terminaba a 180° y se quedaba); ahora
  `FloatingBody3D` tiene `brazo_adrizante` —el GZ de la cabina estanca, que el
  modelo de celdas no representa—, cero por debajo de 45° y pleno pasados 100°,
  multiplicado por la reserva intacta. El barco lo lleva a 3,5 m: vuelve de
  cualquier escora en 1-7 s con la bodega seca y deja de volver al ~65 % de
  inundación, entre la alarma (0,55) y el naufragio (0,85). Señales
  `volcado`/`adrizado` listas para el REVOLCADO de F4. En el mismo repaso salió
  la **quinta regla de flotabilidad**: los brazos se medían desde el origen del
  nodo y no desde el centro de masas, así que el lastre del pesquero no hacía
  nada (par idéntico con el `center_of_mass` arriba, abajo o en el centro) y
  encima restaba; arreglado, el casco pasa de anular su estabilidad a los ~65° a
  hacerlo a los ~78°. `volcado_tests` y `docs/DECISIONES.md`.

- **El parte meteorológico (24-ago-2026):** el clima dejó de ser un valor que
  alguien escribe cada frame y pasó a ser un **guion escrito por adelantado**.
  `ParteMeteorologico` guarda curvas Hermite C1 por canal (furia, lluvia, rumbo
  del frente) y se consulta en CUALQUIER instante; `GeneradorParte` lo redacta
  desde la semilla. La regla que lo ordena todo es del diseñador: **si sube la
  furia no tiene por qué llover, pero si sube la lluvia sí tiene que subir la
  furia** — la lluvia impone un piso (`furia ≥ 6·lluvia`), nunca al revés. La
  hace cumplir el generador al REDACTAR (escribe la furia primero y encaja la
  lluvia bajo las jorobas que le dan piso), no `Ocean`, que sigue tonto.
  **Dos carriles**: sin parte todo se comporta exactamente como antes, y mover
  la perilla de furia con un parte en vigor lo BORRA para toda la tripulación y
  manda lo que puso la mano (decisión de diseño; la perilla de dios sigue siendo
  sagrada). La salida es FINITA: duración sorteada por semilla entre 10 y 25 min,
  y `Ocean.clima_agotado` anuncia el final («se acabó la marea») para que F7 lo
  escuche. Y el mar de fondo SE ADELANTA a la tormenta (§3.3 implementado): las
  bandas largas leen `furia_swell` con energía capada a +1,5 m y el período del
  temporal de origen — el orden de telegrafía real es rayos (900 s) → mar de
  fondo (300 s) → pared de nubes (210 s) → viento. Lo que destraba: los rayos se deciden con la furia
  del spline en el `t0` de su slot — idénticos en las 6 máquinas sin el parche
  de cuantización—; `get_height_at()` deja de tener asterisco (re-espectra con
  la furia que el guion promete para ese instante, sobre un proxy aparte); y el
  `front01` del cielo, implementado y clavado a 0 desde la fase C, por fin sabe
  de dónde y cuándo viene la tormenta. El parte viaja entero en la bienvenida y
  por el canal de debug, porque un cliente sin él vería OTRA tormenta eléctrica
  sin un solo error en consola. Botones por caladero (BAHÍA/BANCO/FOSA/NEGRAS)
  y tecla `P` en el HUD. `tests/parte_tests.tscn` (97 comprobaciones),
  `docs/CLIMA.md` §8 ítem 14 y `docs/DECISIONES.md`.
  Y de paso destrabó el **«lightning jump»** (fase D ítem 12, parcial): la cadencia de rayos de
  cada slot la manda ahora la tormenta que VIENE (`furia_swell`), mientras la distancia y el
  `bolt` los sigue mandando la furia de aquí — así que el horizonte relampaguea 10 minutos antes
  con el mar todavía planchado, y todos esos rayos salen lejanos y sin geometría, sin una sola
  línea de código especial. Del ítem 12 falta el mástil (no existe en el barco), el concepto de
  «metal» y un sistema de daño/reparación.

- **R2, lo barato primero (24-ago-2026):** sin tocar el ciclo de trabajo.
  `Net.Transporte {ENET, STEAM}` es la puerta, y **ENET sigue siendo el defecto a
  propósito**: Steam es una sesión por PC, así que el transporte de Steam se
  llevaría por delante el ciclo de dos ventanas en una máquina —con el que se
  depura todo lo demás— y el loopback de `net_tests`. GodotSteam 4.22 ya está
  vendorizado (win64) y **carga en 4.7.2**: `SteamMultiplayerPeer` existe, que
  era la mitad del spike. Falta el lobby, y `--net-transporte=steam` falla en voz
  alta hasta entonces. Y la **voz**: `VozModel`/`VozProximidad` encogen el radio
  (40 m en calma → 9 m en temporal, menos que la eslora: en el pico no le gritas
  al de proa desde el timón) y cierran el paso-bajo del bus `Voz`; el ruido que
  tapa la voz NO es una curva propia, es `WeatherAudio.ruido01()`. El autoload
  `Microfono` elige aparato —con caída al del sistema cuando desenchufan los
  cascos, que si no te quedas mudo sin enterarte—, lo amplifica de 0 a 200 % y
  deja ver el nivel; su bus nace SILENCIADO para no acoplar.
  Pendiente: lobby de Steam, el transporte de voz (two-voip) y la cancelación de
  eco, que **no está empezada** río arriba. Ver `docs/RED.md` R2.

- **El menú principal (24-ago-2026):** el juego ya arranca por una portada y no
  por el juguete. `game/ui/menu/menu_principal.tscn` es el `run/main_scene`, con
  **el mar de día de verdad** de fondo (el mismo `OceanSurface3D`, el mismo
  cielo y el mismo `DayNightCycle`, con la hora congelada a las 10:30 por el
  nuevo `hora_congelada`) y tres modos: un jugador, hostear y conectarse. Dos
  cosas que no son obvias y que el arnés protege: el menú **deja el mar
  exactamente como lo encontró** —le baja la furia a 1,6 para la foto, porque
  medido con `capture_menu` a la furia de arranque el cielo se encapota y la
  pantalla se va al gris, y la devuelve al abrir la partida; si no, TODAS las
  partidas empezarían con la marejadilla de la portada— más poner `sim_time` a
  cero al empezar, que si no quien tarda diez minutos en decidirse empieza de
  noche; y el ORDEN de las operaciones en red va al revés en cada
  modo — hostear carga el mundo y DESPUÉS llama a `Net.hostear()` (que censa
  `current_scene`), mientras que conectarse llama a `Net.unirse()` desde el menú
  y carga el mundo en `connected_to_server`, para tener dónde decir «no hay
  nadie escuchando». En opciones, los controles se leen del InputMap (una lista
  escrita a mano envejece en silencio) y el micrófono se elige con su medidor de
  entrada, guardado en `user://ajustes.cfg`. `tests/menu_tests.tscn` (74
  comprobaciones), `tests/capture_menu.tscn` para el look y `docs/MENU.md`.
  Pendiente: sonido (regla 10: ElevenLabs) y el lobby de Steam.
- **La partida como sesión (24-ago-2026):** el autoload `Partida`
  (`game/ui/partida.gd`) cierra el viaje de ida del menú. `Esc` abre una tarjeta
  con **Continuar / Volver al menú / Salir**, y `TAB` enseña **quién está a
  bordo con su ping**. Dos cosas que NO son obvias: `Esc` **no pausa nada** —en
  coop no se puede, y en solitario tampoco se hace para que el juego se comporte
  igual solo que acompañado; además, pausar dejaría muerto el HUD de debug, que
  es sagrado (por eso la tarjeta es pequeña, centrada y deja libre la columna
  izquierda)—, y el ping **lo mide el host y lo reparte**, porque un cliente solo
  tiene socket contra el host y el retardo de los demás no lo puede ni aproximar
  (`ENetPacketPeer.PEER_ROUND_TRIP_TIME`, tabla a 1 Hz). Los nombres se presentan
  al conectar y se sanean al recibirlos —vienen de otra máquina—; sin ajustes se
  usa el de la sesión del sistema, que es lo único que distingue las dos ventanas
  del ciclo de trabajo. `Net.desconectar()` es la salida limpia que faltaba, y
  `EstiloMenu` es ahora la fábrica de paleta y cajas compartida por las dos
  pantallas de menú. `tests/partida_tests.tscn` (56), `tests/capture_partida.tscn`,
  `docs/MENU.md` y `docs/RED.md`.
- **Sin commitear ahora mismo:** refactor viewmodel manos→un brazo (player.gd +
  fishing_tests.gd) y borrado de `tmp_down.*`.
- **Grandes pendientes:** red R2 (Steam por SDR y voz por proximidad, detrás de
  la misma puerta `Net`), clipmap del océano (F2), test GPU de paridad con
  golden vectors, olas rebeldes, el barco navegable. Y dos deudas que R1 deja
  anotadas: la máquina de pesca de los compañeros no se replica (ves su cuerpo
  y sus manos, no su caña) y el porteo a dos personas. Detalle y dudas
  abiertas: `docs/DECISIONES.md`.
