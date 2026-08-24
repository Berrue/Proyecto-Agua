# Investigación — El clima del mar antagonista

> Lluvia, truenos, tormenta y viento: cómo funcionan en este tipo de juegos y cómo se implementan
> aquí. Sintetizado de una investigación de 12 agentes (8 dimensiones base + 3 huecos detectados
> por un crítico de completitud), ~90 hallazgos con fuente verificada. Cada afirmación de riesgo
> lleva su fuente; lo que es criterio propio sin fuente directa se marca como tal.
>
> Contexto de código: `Ocean` (autoload, dial de furia 0-10 → Douglas Hs), `OceanWaveProxy`
> (12 Gerstner, JONSWAP sobre banco de fases congeladas), `ocean_surface.gdshader` (bandas
> cuantizadas, espuma por Jacobiano, `fury01`, detail gradient), `TsunamiDirector` (actos),
> `DayNightCycle` (función pura de `sim_time`), `SfxLibrary` (síntesis procedural pre-horneada;
> el clima usa además assets reales — ver §5),
> `CameraFeedback` (presupuesto anti-mareo).

---

## 0 · El principio rector: dos capas, un solo reloj

Toda la literatura converge en la misma separación, y el plano más limpio es el `weather.lua`
de Don't Starve Together (leído el código real):

- **Capa gameplay** (autoritativa o determinista): ¿llueve?, ¿cuánta agua embarca?, ¿dónde y
  cuándo cae el rayo?, ¿cuánto empuja el viento? Se evalúa como **función pura de
  `(sim_time, semilla, furia)`** — exactamente la regla de oro que el océano ya cumple — o la
  decide el host. **Regla operativa: si escribe en el estado del mundo (HP, agua en bodega),
  se evalúa UNA vez en el reloj autoritativo; si solo emite fotones o presión sonora, se evalúa
  localmente.**
- **Capa VFX/audio** (100 % local, jamás replicada): partículas de lluvia, niebla, oscurecimiento,
  sonido. Ningún juego de la industria sincroniza las gotas entre clientes — Lagarde da permiso
  explícito: no hace falta sincronizar gotas↔anillos↔splashes, *"the eye can't see the
  difference"*.

Valheim es la validación directa de nuestra arquitectura: su clima entero es un PRNG determinista
sembrado por el tiempo de juego — idéntico en todos los mundos sin replicar nada; la comunidad
construyó predictores exactos. Sea of Thieves confirma el otro lado: parámetros de ola
server-side + la misma matemática en cada cliente = el mismo mar para toda la tripulación.

**El peligro concreto en Godot: la constante `TIME` de los shaders.** Es un reloj local de render
que diverge entre clientes y no se pausa con la simulación. Cualquier scroll de cortina, fase de
flipbook, paneo de nubes o bandera basada en `TIME` rompe la regla del proyecto. Todo tiempo de
shader debe ser `sim_time` subido como uniform (el patrón que `ocean_time` ya usa) o global
shader parameter — que funcionan también en sky shaders.

Y una sola perilla manda: **el clima entero cuelga del dial de furia**, igual que AC4 Black Flag
colgaba océano y lluvia de la escala Beaufort. `rain01`, `wind_speed`, tasa de rayos, cobertura
de nubes: todos funciones de `fury01` (con matices por acto del director). Un escalar replica
todo el clima.

---

## 1 · La lluvia

### 1.1 Cómo se hace la lluvia en juegos: cuatro capas baratas, no un sistema

La lluvia AAA no es un sistema monolítico: es la suma de 4-5 trucos baratos leyendo el mismo
estado. Los números reales son modestos — Remember Me gastaba **1,69 ms en PS3** en TODO el
efecto (cortinas ~1 ms, splashes 0,33 ms, gotas de cámara 0,32 ms); en GPU actual son décimas.
Presupuesto razonable para nosotros: **≤ 0,5 ms total**.

| Capa | Técnica | Números |
|---|---|---|
| **Cerca (0-15 m)** | GPUParticles3D en caja sobre la cámara, recicladas | caja ~10×0,5×10 m a ~8-15 m sobre la cámara; 2.000-4.000 partículas; caída 15-20 m/s; lifetime 0,6-1,0 s |
| **Media (15-60 m)** | "Sheets": textura con 30-50 trazos horneados en un quad de 5×5 m (truco de Abandon Ship: 20 sheets parecen 1.000 gotas) | opcional en F1; la cortina puede bastar |
| **Lejos (60 m+)** | Cortina: cilindro invertido pegado a la cámara con 2-3 capas de la misma textura de streaks a escalas/velocidades distintas (Remember Me, ToyShop) | radio 30-60 m, unshaded, `cull_front`, scroll `UV.y = sim_time * v_capa` |
| **Atmósfera** | Niebla más densa Y desaturada | `fog_light_color → lerp` hacia su luminancia con `rain01`; `fog_density` extra sobre lo que dicta el acto |

**La gota nunca se dibuja como gota: se dibuja como trazo.** Una gota real cae a ~9 m/s; a 1/60 s
de exposición es un streak de ~15 cm — los juegos lo exageran 2-4×. El blur se hornea en la
textura (Remember Me: streaks pre-difuminados de fábrica), no se calcula.

**Cómo se hace visible (el problema real de la lluvia):** una gota refracta ~165° de entorno,
cielo incluido, así que es MÁS brillante que el fondo — y casi invisible contra fondos claros.
Los juegos no simulan esto: suben brillo/alfa artificialmente y oscurecen el cielo al llover para
regalar contraste. **La regla toon (BotW, Wind Waker): pocas gotas, gordas, de alfa alto
(0,6-0,9), con cutoff duro** — no la neblina de miles de gotas al 0,1 de alfa del fotorrealismo.
Con nuestro cielo por bandas el contraste es exacto y controlable: **el color de la lluvia se
elige 1-2 bandas más claro que la banda del cielo de tormenta**. Bonus barato de contraluz:
multiplicar el brillo del streak por `dot(view_dir, sun_dir)` remapeado — al mirar hacia el
sol/luna/relámpago la lluvia "se enciende", el mismo principio que nuestro specular de blob duro.

### 1.2 La lluvia SOBRE EL MAR — lo que la hace leerse como lluvia y no como "más tormenta"

No hay charcos ni suelo que mojar: el reto es distinto, y la física real es contraintuitiva y
utilísima porque dicta el look:

1. **La lluvia CALMA el mar corto** ("rain knocks down the sea", confirmado en literatura:
   Nature 1989, J. Phys. Oceanography 1992, GRL 2020): amortigua las olas de ~10 cm vía
   turbulencia y burbujas, y suprime rompientes de las olas largas.
2. **Y a la vez lo hace "hervir" fino**: siembra ring waves de alta frecuencia y baja amplitud.
   La superficie queda picada, mate, sin sparkle.
3. **Mata el brillo**: el highlight solar/lunar se fragmenta en moteado y pierde intensidad.

Traducido a nuestro shader — todo con un uniform `rain01`, y en este orden de impacto por coste:

1. **Matar/encoger el blob especular** (casi gratis, señal enorme): `spec_size × (1 − 0,5·rain01)`,
   intensidad `× (1 − 0,7·rain01)`. "Romper el specular" es la señal nº 1 de lluvia sobre agua.
2. **Atenuar el detail gradient existente a ~30-50 %** (las olas cortas mueren) y **subir un pelín
   el umbral de la espuma de Jacobiano** (menos rompientes). Contraintuitivo, pero es lo que la
   hace real: vende "lluvia" en vez de "más furia".
3. **Moteado de espuma en albedo** ("sal y pimienta"): en un agua toon OPACA por bandas, la señal
   más legible va en ALBEDO, no en normal (la cuantización se come la normal). Puntos/aros del
   color de espuma existente con el mismo borde duro (`step`, no `smoothstep`), vida corta
   (0,3-0,6 s), densidad ∝ `rain01`, generados con hash de celdas sobre
   `(world_xz, sim_time, semilla)` — función pura, idéntica en los 6 clientes gratis.
4. **Anillos procedurales** (la técnica canónica, Lagarde/Remember Me + Cyanilux): celdas tipo
   Voronoi, un anillo por celda con `pow(saturate(1 − abs(d − t)), 8) · sin((d − t)·30)` y offset
   temporal por celda; 4 capas cuyos pesos crecen con la intensidad. En vivo es función pura de
   `(world_xz, sim_time, hash(semilla))`; si pesara, se hornea a flipbook de 16 frames al arrancar
   (nuestra filosofía exacta: como el audio). La normal de anillos se conserva SOLO para trocear
   el specular; el frente del anillo se usa como máscara de albedo → aros blancos nítidos estilo
   Wind Waker. Atenuar por huella en pantalla como ya hace el detail gradient (son sub-píxel a 100 m).
5. **Splashes cerca del barco** (radio 15-25 m): un solo flipbook para todos (ToyShop usó UNA
   secuencia de gota de leche para miles de partículas; escala/alfa/flip de U aleatorios ocultan
   la repetición). Como el océano es puro, cada splash se clava EXACTO en la superficie evaluando
   la misma suma Gerstner en el vertex shader de la partícula. Posición/fase desde
   `hash(celda, floor(sim_time·rate), semilla)`.

**La intensidad** (corregido 2026-08-23, decisión de diseño): la lluvia es **INDEPENDIENTE de la
furia** — furia 9 con cielo seco es un estado válido, y la tabla de §3.4 describe lo que la furia
*habilita*, no lo que fuerza. `rain01` sale de `rain_level` (el parte meteorológico — hoy el
debug, en fase D el mutador por semilla de DISENO §variedad) × `rain_scale` del director:
**RETIRADA la corta en seco** — el silencio súbito de la lluvia es telegrafía extra del tsunami,
gratis.

### 1.3 Setup Godot 4 concreto (con los gotchas verificados)

Checklist del nodo de lluvia:

```text
GPUParticles3D
├─ amount: 3000-4000 (dimensionado para furia 10; JAMÁS cambiarlo en runtime: resetea el sistema)
├─ amount_ratio: curva_lluvia(fury01)      ← EL dial; no resetea (4.2+)
├─ lifetime: 0.8   · fixed_fps: 30 + interpolate (mitad de coste; nadie lo nota en gotas)
├─ preprocess ≈ lifetime                    ← arranca con la cortina llena, no "llueve desde cero"
├─ local_coords: false                      ← si no, el efecto "pecera": la lluvia gira con la cámara
├─ visibility_aabb: AABB(-40,-40,-40 → 80,80,80)  ← default 8 m: culling Y mata la colisión GPU (#93567)
├─ transform_align: Z_BILLBOARD_Y_TO_VELOCITY     ← la gota se alinea a su trayectoria
├─ use_fixed_seed: true, seed: hash(semilla, "rain")   (4.3+)
├─ draw_pass: QuadMesh 0.02×0.4 m, material unshaded SIN billboard
│    (el billboard del material SOBREESCRIBE el align a velocidad — bug confirmado #84753)
│    y SIN transparencia real: alpha scissor / quads opacos → pipeline opaco
│    (en Forward+ el enemigo es el overdraw transparente, no el nº de partículas: #97903)
└─ ParticleProcessMaterial
     ├─ emission_shape: BOX, extents (10, 0.5, 10), a ~8-15 m SOBRE LA CÁMARA (no sobre el mar: Hs llega a 25 m)
     ├─ gravity: (viento.x, -20..-25, viento.z)   ← la inclinación por viento es UN vector; con align_y las gotas se inclinan solas
     └─ NADA de turbulence (ruido 3D "con alto coste en GPU" según docs; para ráfagas basta animar gravity)
```

El emisor **sigue la POSICIÓN global de la cámara, nunca su rotación** (el barco cabecea de
verdad: si hereda rotación, la cortina entera se inclina con el cabeceo y delata el truco), con
snapping opcional a rejilla de 1-2 m para que el volumen no "respire".

**Que no llueva dentro de la cabina**: 1-3 `GPUParticlesCollisionBox3D` hijos del barco cubriendo
el techo, con `collision_mode = HIDE_ON_CONTACT` y `collision_base_size` 0,1-0,25. Los
box/sphere son analíticos y se mueven en tiempo real (artículo oficial de 4.0) — cabecean con el
barco gratis. El `HeightField` (la técnica estándar en mundos estáticos) queda descartado: con
geometría móvil re-renderiza profundidad siempre; el SDF exige bake y no puede hornearse para una
pose que rota. Si las gotas tunelean el techo: subir `fixed_fps` a 60 o engordar la caja.

**Splashes sobre el mar: NO usar sub-emitters At Collision** — ningún collider GPU evalúa nuestra
función analítica, y el `amount` del sub-emitter es un presupuesto global compartido con trampas
documentadas. Sistema plano independiente pegado a `ocean_height()` (§1.2.5). Sub-emitter queda
bien solo para cubierta/techo (colliders box), con amount ≥ 4× lo esperado.

### 1.4 La lluvia como mecánica: llena el barco

La lección de Sea of Thieves (la referencia del género): **dentro de la tormenta, la lluvia llena
las cubiertas inferiores y hunde el barco si nadie achica** — el borde ("Light Storm") llena
lento, el centro ("Heavy Storm") rápido; la inundación PERSISTE al salir. Es la conexión directa
con nuestra bomba de achique (DISENO §el segundo verbo): la lluvia debe costar algo.

Implementación: un solo `water_level` (float) del host — entradas = lluvia (goteo lento, función
de `rain01`) + olas sobre borda + vías de agua; salidas = bomba/cubo/imbornales. **Cero
simulación de fluidos, y JAMÁS acoplado a las partículas del cliente** (§7). Los clientes derivan
todo lo visible de ese float.

### 1.5 Lluvia y presupuesto anti-mareo (criterio propio, sin fuente directa)

- **Nada de distorsión refractiva de pantalla** (gotas en lente estilo Remember Me): generador
  conocido de incomodidad + nuestra agua ya prohíbe screen texture. Si se quieren gotas en
  cámara: 2-3 discretas, opacas, toon, en un CanvasLayer.
- **Máscara radial de pantalla** (`SCREEN_UV`) en cortina y partículas: atenuar alfa hacia los
  bordes — los streaks rápidos en periferia son exactamente el flujo óptico que la viñeta ocluye.
  La lluvia vive en el centro de la visión.
- **El viento que inclina la lluvia cambia con suavidad** (lerp sobre segundos de `sim_time`): un
  cambio brusco de inclinación global se lee como rotación de cámara aunque no lo sea.
- A favor: la cortina cilíndrica es de baja frecuencia y no rota con la cámara (la capa más
  segura), y la niebla densa REDUCE el flujo óptico periférico — la tormenta ayuda al confort.

---

## 2 · Truenos y relámpagos

### 2.1 El flash: luz + cielo, multi-pulso, y 3:1 de resplandores por cada rayo visible

- **Pulsar la luz direccional NO basta** (postmortem kmonkeygames): de noche "el cielo no se
  ilumina" y la ilusión muere. Los mandos en Godot: `DirectionalLight3D.light_energy` (×2-4) +
  `Environment.background_energy_multiplier` + `ambient_light_energy`. Considerar una segunda
  `DirectionalLight3D` "LightningLight" sin sombras (evita re-render del shadow map en un pulso
  de 2 frames — criterio propio).
- **Envolvente realista = multi-pulso**: un rayo real tiene 3-4 return strokes separados
  40-50 ms, duración mediana ~0,52 s. En bandas se lee perfecto: banda+2, banda+0, banda+1,
  banda+0. **Capar a 3 pulsos por evento** (§2.5).
- **El 75 % de los rayos reales son intra-nube**: resplandor difuso sin bolt (sheet lightning).
  Presupuesto: **por cada bolt con geometría, 3-4 sheet flashes solo-cielo**, con dirección — un
  blob de resplandor en el azimut del strike (`pow(max(dot(EYEDIR, lightning_dir),0), k)`) sumado
  ANTES de la cuantización del cielo: los jugadores VEN de qué lado viene la tormenta.

**El flash en look toon: promoción de banda, no bloom.** Sumar `lightning01` al término de luz
ANTES de cuantizar, en TODOS los materiales toon (global shader parameter): todos los píxeles
suben 1-2 bandas de golpe y vuelven — el lenguaje exacto del cel de anime con paleta aclarada.
Ventajas medibles: el delta de luminancia por banda es un número de paleta (el criterio WCAG se
audita offline contando bandas); la espuma jacobiana ya-blanca actúa de reflejo del relámpago en
las crestas, gratis; el specular puede ensancharse un paso (el mar "centellea"). Durante el
flash, ATENUAR el detail gradient (`× (1 − lightning01)`): el frame de flash queda plano y limpio
como un cel, y reduce el parpadeo de alta frecuencia (lo peligroso fotosensiblemente). **Lo que
NO hacer: `adjustment_brightness`, glow/bloom** — gradientes continuos que rompen las bandas y
hacen el delta impredecible.

### 2.2 El bolt visible

- **Generación**: midpoint displacement (parámetros del tutorial clásico de Tuts+: sway,
  suavizado entre puntos, ramas a ±30° alternando lado, afinadas hacia la punta) → pre-generar
  **4-6 texturas SDF de bolts al arrancar** en un SubViewport, sembradas de la semilla global —
  la misma filosofía que el audio pre-horneado.
- **Render** (receta hexaquo para Godot): quad billboard con la textura SDF recortada con
  `step()` (borde DURO cuantizado, no `smoothstep`), `y_progress` revela el rayo de arriba abajo
  en ~100 ms, `OmniLight3D` opcional en el impacto (sin sombras, radio corto).
- **Vibración sin regeneración**: 2-3 variantes SDF del mismo camino alternadas por frame.
- **Afterglow toon**: escalones discretos (2-3 frames blanco pleno → 100-200 ms en la banda clara
  del cielo → fuera), nunca fade continuo de alfa.
- **El impacto siempre toca algo**: el océano es consultable — el bolt se orienta del cielo a la
  cresta (o al mástil) exacta en ese `(x, z)`.

### 2.3 El timing flash→trueno: la telegrafía que casi nadie hace bien

Sonido a ~343 m/s → **3 s por km**. La mayoría de los juegos reproducen el trueno simultáneo
(queja recurrente); Sea of Thieves lo hace bien y se nota. Para nosotros es un regalo
arquitectónico: cada evento de rayo se deriva de `(sim_time, semilla)` con posición mundial; el
flash se muestra en `t0` y **cada cliente agenda SU trueno en `t0 + dist(oyente, rayo)/343`** —
cero red, imposible de desincronizar, y contar segundos se vuelve instrumento de navegación.
La progresión dramática: TORMENTA temprana = rayos a 3-5 km (gap 9-15 s, solo rumble); escalada
= 1 km (3 s); clímax = strike en el barco con flash y bang SIMULTÁNEOS — **la convergencia del
intervalo hacia cero ES la barra de progreso diegética de la tormenta.**

### 2.4 Cadencia y el rayo como mecánica

- **Programación**: proceso de Poisson determinista por slots de 4-8 s:
  `r = hash(semilla, "bolt", floor(sim_time/slot))` decide si hay evento, tipo (sheet/bolt),
  azimut, distancia y semilla de geometría (patrón del mod Thunderhead: misma semilla de rayo →
  mismo bolt en todos los clientes). Tasa por furia: F3-4 → 1 flash lejano/30-40 s (solo sheet);
  F6 → 1/10-15 s con bolts; F8+ → 1/5-8 s cercanos. Consultable a futuro: el director puede
  "reservar" un rayo dramático mirando los slots próximos.
- **La "lightning jump" real** (NASA/NOAA): un salto brusco de frecuencia de rayos precede a la
  meteorología severa por 10-30 min — la naturaleza usa la cadencia como telegrafía. En el acto
  RETIRADA/AVISO: duplicar la tasa de sheet lightning silencioso en el horizonte mientras el mar
  se retira.
- **Mecánica** (el patrón lo definen SoT y BotW; Raft demuestra que el rayo-decorado no genera
  historias): SoT — 20 de daño, 70 con el sable EQUIPADO, y equiparlo atrae el rayo; golpea a
  través del casco; detona pólvora. BotW — el metal equipado **chisporrotea con arcos crecientes
  varios segundos antes** del impacto; contrajuego: desequipar o lanzar el arma como señuelo.
  Cuando el strike depende de decisiones se percibe justo; aleatorio se percibe injusto.
  Receta para nosotros: (1) el rayo busca el punto más alto → el MÁSTIL por defecto, dañando
  aparejo/antena → tarea de reparación coop, no muerte instantánea; (2) telegrafía BotW: 3-5 s
  antes, los objetos metálicos chisporrotean (arcos toon + siseo procedural) — tiempo justo para
  soltar el bichero; (3) herramienta metálica EN LA MANO en cubierta = atrae (decisión, no azar);
  (4) por debajo de furia 6, solo decorado lejano. El único dato del host: si el strike programado
  "encuentra" barco/jugador (re-targeting, como DST pondera jugadores y Minecraft re-apunta).

### 2.5 Seguridad fotosensible: números duros (no negociable con nuestro presupuesto sensorial)

Xbox Accessibility Guideline 118 (la referencia AAA) + WCAG 2.3.1:

- Un "flash" = cambio de luminancia ≥ 10 % con estado oscuro < 0,8. **FALLA con más de 3 flashes
  en cualquier ventana de 1 s** ocupando ≥ 20-25 % de pantalla. Rojo saturado: umbral más
  estricto — **nada de relámpagos rojizos**.
- El triple pulso realista está EXACTAMENTE en el límite → **hacer cumplir en el sampler
  determinista** (no confiar en tuning): máx 3 pulsos por evento, eventos separados ≥ 1 s
  (mejor 2 s).
- **Toggle "Reducir relámpagos"** — NUNCA etiquetado "apto para epilepsia" (responsabilidad
  legal; regla de Game Accessibility Guidelines): sustituye el multi-pulso por una rampa única
  de ~50 ms subida / 300 ms caída con delta a la mitad. El trueno, el bolt estático y toda la
  telegrafía sobreviven → la opción no penaliza jugabilidad.
- Checklist de release: pasar PEAT (gratuita, Trace Center) o Harding sobre capturas del clímax.

### 2.6 El trueno (resuelto con assets — la receta queda como referencia)

**El trueno ya no se sintetiza: hay cuatro WAV reales en la biblioteca (§5).** Lo que sigue es el
modelo publicado, que se conserva por dos motivos: describe la anatomía por la que se eligió y
recortó cada clip, y es el plan B si hiciera falta una variante que no tenemos.

El mejor modelo señal-based publicado (Fineberg et al. 2022, arXiv 2204.08026; 6,15/10 de realismo
vs 8,17 la grabación real, mejor que Farnell) usa 4 capas — y el trueno es casi todo **< 1,2 kHz**,
dato que sigue mandando en la mezcla:

| Capa | Receta | Números |
|---|---|---|
| **Crack** (multi-strike) | ruido blanco por bandpass Q≈7-10 con centro deslizando | 1300→650 Hz, ataque < 5 ms, 50-150 ms, uno por pulso del flash |
| **Rumbler** (el cuerpo) | ruido marrón (`y = 0.985·y + 0.02·x`) por lowpass ~120-150 Hz, decay 6-10 s × ondulación lenta (ruido LP a 0,5-2 Hz, profundidad 40-70 %) — el "rodar" | `tanh` suave antes del filtro final lo engorda gratis |
| **Afterimage** (cola) | banda 300-350 Hz muy tenue | decay 12-15 s |
| **Deepener** (sub) | capas 15-80 Hz, Q 3 | decay ~18 s |

Lo que de este modelo **sigue vigente con los assets reales**: el evento de rayo elige variante
por distancia y el retardo es `d/343` de cada oyente (§2.3); cerca manda el crack y lejos solo el
rumble, porque el aire absorbe los agudos con la distancia — por eso `trueno_seco` (4 s, todo
ataque) sirve de impacto cercano y `trueno_rodante` (16,3 s, sin transitorio inicial) de tormenta
lejana. Si hiciera falta una variante "muy lejana" que no tenemos, sale de filtrar `trueno_rodante`
con un lowpass a 150-300 Hz en vez de generar nada. El chisporroteo de telegrafía (metal
pre-strike) sí queda pendiente de síntesis: son ráfagas de impulsos con densidad creciente,
trivial de hornear.

---

## 3 · La tormenta como categoría

### 3.1 Qué hacen los referentes

- **Sea of Thieves** (el modelo del género): la tormenta es *"una cosa física grande en el
  mundo"* (Rare) — una REGIÓN con nube 3D visible a kilómetros que recorre un camino fijo en
  bucle (~4 h reales), sincronizada entre servidores. **Gradiente en dos anillos**: borde (Light
  Storm) = lluvia ligera que ya llena la bodega + cielo oscuro; centro (Heavy Storm) = la campana
  repica sola, TODAS las brújulas giran, el timón tira y exige a alguien sujetándolo, el agua
  entra rápido, rayos con daño. Recompensa exclusiva dentro (Stormfish). La inundación persiste
  al salir. Sus nubes: mallas art-directed SIN raymarching, y la tormenta es literalmente una
  malla retorcida rotando cuyo vertex lighting responde a los flashes.
- **World of Warships**: la tormenta como **modificador de información** con números
  (visibilidad capada, detección −10 %, dispersión +30 %) y como volumen oclusor (afecta solo a
  líneas de visión que la cruzan).
- **Valheim**: clima = PRNG determinista del reloj de mundo (nuestra arquitectura), viento
  0,05-1,0 modulando las olas, y la furia como multiplicador de amenazas (+5 % spawns con
  tormenta).
- **Raft**: máquina de estados con probabilidades y la niebla en un canal SEPARADO superpuesto a
  cualquier estado (multiplica variedad percibida con un parámetro) + "Motion Sickness Mode" que
  reduce las olas VISUALES sin tocar la simulación.
- **Sailwind/Windbound**: la tormenta cambia la NAVEGACIÓN (rizar velas, elegir rumbo; olas que
  cubren rocas antes visibles) y abre el verbo de **preparar el barco**.
- **Barotrauma** (hallazgo negativo útil): no tiene meteorología — su "tormenta" es la avería en
  cadena interna. El patrón robable: en el pico de furia, averías deterministas (bomba atascada,
  parpadeo de luces, radio con estática), cada una una tarea de 30-60 s en un lugar DISTINTO del
  pesquero — separar a la tripulación cuando comunicarse es más difícil = pico de tensión.

### 3.2 Global vs localizada: la decisión

Para una sesión de 25-35 min con un director dramático de actos, **furia GLOBAL como espina
dorsal** (ya existe; todos viven el mismo clímax; replicación y determinismo triviales; un dial
audita todo el mix) **+ 1-2 celdas de chubasco (squall) locales** puramente cosmético-tácticas:
posición = path paramétrico de `(sim_time, semilla)`, radio 300-600 m, +1..+2 de furia local
*percibida* (lluvia más densa, trueno más cercano, menos visibilidad) **sin tocar el océano
global** — las olas siguen siendo una única función pura y la física no se fragmenta. La celda da
el momento SoT ("¡mira esa cortina a estribor!") y una decisión de rumbo; el director puede
"aparcar" una celda sobre el barco para justificar el pico local. Consultable a futuro como todo
lo demás.

### 3.3 La rampa meteorológica REAL (y es contraintuitiva)

Orden real de un temporal acercándose por mar — **el error típico de los juegos es empezar por la
lluvia**:

> **Estado (24-ago-2026): IMPLEMENTADO.** `wave_proxy.set_sea_state()` acepta ahora una mar de
> fondo aparte (`hs_swell` + `hs_origen`): las bandas **≥150-250 m** leen la furia que VIENE
> (`Ocean.furia_swell`, ventana de 300 s) con la **energía capada a +1,5 m** sobre el mar del
> momento (`PRECURSOR_HS_MAX`, decisión del diseñador) pero el **período de la tormenta de
> origen** — que es la definición física del swell: energía moderada, período de temporal lejano.
> Sin ese matiz no funciona, y se midió: normalizado a su Hs capado, el precursor pica en olas de
> ~50 m, la máscara de bandas largas lo filtra entero y el «anuncio» es exactamente **cero**.
> El rizado corto no se entera (es del viento de AHORA), y sin parte todo es un no-op **bit a
> bit** — las dos cosas con test en `parte_tests`. *(Ojo: una versión anterior de esta sección
> afirmaba que el espectro JONSWAP «ya produce» esta rampa por sí solo. Falso — medido: a furia 2
> los tres modos largos valen 0,0000 m. La producen el parte + este cableado, no el espectro.)*

1. **El mar de fondo llega PRIMERO** (swell largo de período 10-15 s, hasta 72 h antes: las
   ondas largas viajan más rápido que la tormenta).
2. El barómetro cae (≥ 4 hPa en 3 h = temporal).
3. El cielo se vela de arriba abajo (cirros → velo → altostrato).
4. **El trueno se OYE a 16-24 km antes de verse el rayo de día** (y el rayo puede caer a 40 km
   de la lluvia: los primeros truenos llegan antes que ninguna gota).
5. El viento arrecia y el mar de viento corto tapa el swell (mar confusa).
6. **Por último** la lluvia fuerte y los rayos cercanos.

**Regla de oro robada de la realidad: EL MAR CAMBIA ANTES QUE EL CIELO, Y EL CIELO ANTES QUE LA
LLUVIA.** Y nuestro espectro ya lo hace solo: en JONSWAP, al subir el viento el pico ω_p se
desplaza a frecuencias bajas — la energía nueva entra primero por las bandas LARGAS mientras la
cola corta está saturada. La rampa "olas largas primero" es física gratis, no una heurística
(`wave_proxy.set_sea_state` ya la produce).

### 3.4 Tabla maestra: el dial de furia manda todo el clima

Douglas (mar) + Beaufort (viento, NOAA) + lluvia (WMO) + fenómenos, atados al dial. Nuestro dial
0-10 ya ES Douglas 0-9 + un punto 10 "fenomenal". Correspondencia WMO 1955: D3≈B5, D4≈B6,
D5≈B7-8, D6≈B9-10, D7≈B11, D8-9≈B12.

| Furia | Hs (m) | ≈Beaufort (viento m/s) | Lluvia (mm/h) | El mar se ve | Clima/eventos |
|---|---|---|---|---|---|
| 0 | 0 | B0-1 (0-1,5) | 0 | espejo | — |
| 1 | 0,1 | B2 (2-3) | 0 | rizado vidrioso, **cat's paws** | — |
| 2 | 0,5 | B3 (4-5) | 0 | crestas empiezan a romper | swell largo si viene tormenta (§3.3) |
| 3 | 1,25 | B4-5 (7-10) | 0 | **borreguillos** (espuma jacobiana arranca) | cielo se vela; primer trueno LEJANO (solo audio) |
| 4 | 2,5 | B5-6 (10-13) | 0-ligera | muchos borregos | viento audible; banderas; specular apagándose |
| 5 | 4,0 | B6-7 (13-16) | 2,5 | spray; **estrías de espuma** empiezan | silbido de jarcia entra; llovizna |
| 6 | 6,0 | B8 (18-21) | 7,5 | espuma extensa, estrías marcadas | lluvia franca; sheet lightning; rayos reales desde aquí |
| 7 | 9,0 | B9 (22-24) | 15 | **spindrift** en las crestas | bolts cercanos; pesca "heroica" (DISENO) |
| 8 | 14 | B10-11 (26-30) | 50 | estrías densas | strikes al barco posibles; visibilidad cayendo |
| 9 | 18 | B12 (33+) | 50+ | **superficie generalmente blanca** | aire lleno de spray (+fog); voz enmascarada |
| 10 | 25 | fuera de escala | violenta | fenomenal | tsunami / clímax |

Cada fenómeno es un `smoothstep` sobre `fury01` con su umbral: **un solo uniform gatea toda la
escalera.** La columna "aspecto del mar" de Beaufort es la curva de calibración gratis del
patrón de espuma.

### 3.5 Tormenta y verbos: qué abre, qué cierra

**Abre** (coop físico): achicar, sujetar el timón que tira, trincar/preparar (checklist de
60-90 s que convierte la telegrafía en gameplay), navegar por oído, la pesca exclusiva de
tormenta (nuestras legendarias de furia ≥ 7 ya lo son). **Cierra** (información): ver lejos,
leer instrumentos, y — clave — **comunicarse**.

**El enmascaramiento de voz como mecánica estrella**: el volumen de las camas (viento+lluvia+mar)
define, en la misma curva, la atenuación del bus de voz de proximidad — radio útil ~40 m en F0 →
8-10 m en F9, con lowpass en el bus de voz (la voz "rota" por el viento) y otro lowpass en las
camas bajo cubierta (**refugio = volver a oírse: razón acústica para reunirse dentro**). En el
pico, las órdenes complejas fallan y emergen los gritos de una palabra y las señales físicas — el
juego de gritos se convierte en juego de pantomima: eso ES el clímax coop. Escalonar los
umbrales para que nunca se cierren todos los verbos a la vez.

**Señalización diegética gratis** (SoT): cualquier objeto físico que reacciona al viento — la
campana que repica sola, la driza golpeando el mástil, la puerta que bate — es telegrafía
derivable de `fury(sim_time)` sin UI. (DISENO ya lo pide: "el barco es el HUD".)

### 3.6 El cielo de tormenta (el hueco que detectó el crítico — la mitad superior de la pantalla)

- **Arquitectura Godot**: sky shader custom (`shader_type sky`) con `Sky.process_mode = REALTIME`
  y `radiance_size = 256` (límite duro del modo; es EL modo diseñado para cielos que cambian cada
  frame). ⚠️ **Hay que ponerlo A MANO en el recurso `Sky`.** El default es `AUTOMATIC`, que elige
  REALTIME solo si el shader usa `TIME` o `POSITION`; si el shader se alimenta de **uniforms
  propios** (nuestro caso: `sky_time` en vez de `TIME`, por la regla del reloj) elige
  **INCREMENTAL**, que amortiza el muestreo sobre varios frames y con un cielo que muta cada
  frame deja la luz ambiente permanentemente desfasada, bombeando. Se coló en la primera
  implementación y lo cazó una pregunta del usuario sobre las fuentes; ahora hay test que exige
  REALTIME en las dos escenas.
  *Nota sobre una fuente que circuló en la investigación*: el PR godotengine/godot **#55933**
  ("Add High Quality Once update mode to Sky") está **abierto y nunca se fusionó** — lo movieron
  a 4.x pendiente de rediseño, así que ese modo NO existe. Sirve solo por sus medidas de coste
  (23 FPS con radiancia de alta calidad continua frente a 657 con generación única), que son la
  razón de fondo para no acercarse a `QUALITY` en un cielo animado. Nubes en `use_half_res_pass` (1/4 de píxeles; la cuantización esconde el upsampling).
  **En `AT_CUBEMAP_PASS`, versión simplificada sin detalle fino** (solo gradiente + cobertura
  media + oscurecimiento direccional): elimina el shimmer del ambient con el scroll. Los global
  uniforms (`sim_time`, `fury01`, `wind_dir`) funcionan en sky shaders.
- **Nubes**: fbm de 5 octavas con **corte duro toon**
  `smoothstep(cutoff, cutoff + fuzziness, noise)` y 2 colores por nube;
  `coverage01 = pow(fury01, 0.7)` → `cutoff = mix(0.62, 0.12, coverage01)`,
  `fuzziness = mix(0.10, 0.03, coverage01)` — al cerrarse el cielo los bordes se ENDURECEN.
  Truco Wind Waker: dos capas del mismo ruido a velocidades distintas (1× y 0,6× con otra
  escala) = nubes que evolucionan gratis. Scroll con `wind_dir · wind_speed · sim_time`; offset
  de dominio por semilla.
- **Orden de composición**: gradiente día/noche (por `LIGHT0_DIRECTION.y` — hereda la hora del
  `DayNightCycle` gratis) → mezcla a paleta de tormenta (desaturar hacia luminancia + oscurecer
  40-60 % por `coverage01`) → capa de nubes → **inyectar flash aditivo** → **cuantizar bandas AL
  FINAL** — así el flash promociona bandas también en el cielo, la misma regla que el agua.
- **El frente de tormenta en el horizonte** (telegrafía SoT sin geometría): banda direccional en
  el domo — `front = smoothstep(cos(half_arc), 1, dot(EYEDIR_xz, storm_dir))` × máscara de
  altura, silueta de cumulonimbos recortando un fbm de MUY baja frecuencia en el borde superior.
  `wall_top = mix(0.02, 0.35, front01)`: **el muro CRECE del horizonte conforme se acerca.**
  `front01` es un global SEPARADO de `fury01` (en el AVISO el muro puede crecer aunque la furia
  local baje — la retirada engañosa).
- **Sheet lightning**: emissive en la capa de nubes del propio sky shader
  (`cloud_mask · lightning01 · dir_mask`) — las zonas densas brillan más, coste ~cero.
  **Volumetric fog descartada para flashes**: los docs advierten ghosting por reproyección
  temporal con luces breves, y el froxel buffer tiene coste base fijo.

---

## 4 · El viento

Ya existe como dato (`wind_direction_deg` alinea el espectro en `wave_proxy.generate()`); falta
hacerlo **visible, audible y jugable**.

### 4.1 El modelo: vector global + rachas por ruido — nadie simula fluidos

Ghost of Tsushima: un único vector de dirección y **solo la magnitud respira con Perlin sobre el
tiempo** — las rachas cruzando los campos salen de eso. El espectro real (Van der Hoven 1957)
tiene el pico de rachas en períodos de ~1 min con energía entre 1-100 s, y un hueco espectral en
6-60 min (el viento medio es estable a esa escala → la dirección base cambia por acto, no
continuamente).

```gdscript
# WindState — función pura, evaluada por frame en GDScript en CADA cliente (mismo código, mismo resultado).
# gust01 por suma de senos (NO FastNoiseLite compartido CPU/GPU: floats divergen entre implementaciones):
gust01(t) = 0.5·n(t/45) + 0.35·n(t/12 + 7.3) + 0.15·n(t/2.5 + 31.7)   # n = suma de 4-6 senos, fases del seed
wind_speed = base(fury01) · (1 + k·gust01)     # base según tabla Beaufort §3.4
wind_dir   = dir_por_acto ± 10-15° · octava_lenta   # girar rápido la dirección marea la lectura
```

Al shader se suben como **uniforms escalares** (`wind_dir`, `wind_speed`, `gust01`) — el shader
solo evalúa ruido ESPACIAL, nunca el temporal (evita divergencia CPU/GPU). Como es suma de senos,
`gust01(sim_time + 5)` es **consultable en el futuro** igual que el océano: el silbido y la
mancha oscura pueden anticipar la racha, la misma telegrafía que el tsunami.

Y el precedente AAA que da permiso para simplificar: **en AC3/AC4 la dirección real del viento NI
SIQUIERA mueve las olas** ("designers controlled it separately") — el viento percibido lo venden
la espuma, el spray y las velas. Nadie lo notó. Si rolar el mar entero se complica, es legítimo
dejar las direcciones de ola cuasi-fijas por sesión y vender el viento con los fenómenos de §4.2.

### 4.2 El viento HECHO VISIBLE en el mar (escalonado por Beaufort, gateado por furia)

**(a) Cat's paws — el hallazgo de mayor valor estético/mecánico por línea de código.** Una racha
que toca el agua eriza ondas capilares que se ven como **manchas oscuras y mates avanzando con la
racha** (la micro-rugosidad desvía el reflejo del cielo). Los navegantes de vela las usan como
predictor: **ves la racha venir antes de sentirla**. En el shader existente:

```glsl
float gust_mask = step(umbral, noise((world_xz - wind_dir·wind_speed·sim_time) / 35.0));
// dentro de la mancha: detail_gradient ×2-3 (el agua se eriza),
// RESTAR ~0.5 al escalar que se cuantiza (cae UNA banda con borde duro — no multiplicar albedo),
// y encoger el blob specular.  Gate: campana de furia ~1-4 (en mar alto quedan enmascaradas).
```

El umbral se liga a `gust01(sim_time)`: la mancha EXISTE solo cuando hay racha, todas las
máquinas ven la misma en el mismo sitio, y el jugador a barlovento la ve venir — telegrafía de
racha idéntica en espíritu a la del tsunami.

**(b) Estrías de espuma (foam streaks / windrows) — Beaufort 7+.** NOAA: "foam blown in streaks
downwind" — líneas blancas paralelas al viento, EL rasgo que distingue tormenta de mar
simplemente grande. Ruido anisótropo: comprimir la coordenada de muestreo ~2 m transversal ×
40 m longitudinal (anisotropía 10-20×), avanzando con el viento; entra como `max()` en el patrón
de espuma existente ANTES de la cuantización — comparte el borde toon. Densidad gateada: 0 bajo
furia ~5-6, creciendo hasta que en furia 9-10 el ramp colapsa hacia blanco ("surface generally
white" — el final visual del acto TORMENTA).

**(c) Spindrift — Beaufort 8+.** El viento arranca la cima de las olas en velos horizontales a
sotavento. `GPUParticles3D` con emisión por script: cada 0,2-0,5 s, muestrear una rejilla gruesa
(8×8, radio 80 m) y donde el Jacobiano marque cresta rompiente, burst one-shot en la cresta
(la MISMA consulta que ya alimenta la espuma); velocidad inicial `wind_dir · wind_speed · 0.8`,
vida 0,5-1 s, billboard blanco plano cuantizado. Gate: furia ≥ 7. Posiciones deterministas
(derivan del océano puro); la animación interna es cosmética local.

**(d) Banderas y telas — el indicador nº 1 de lectura, sin cloth sim.** Técnica GDQuest: en
`vertex()`, noise texture desplazada por el tiempo, multiplicada por `UV.x` (ancla el borde del
mástil, libera el de fuga); refinamientos de Victor Karp: máscara de rigidez en vertex colors
(para cabos y redes) y desfase por world position (dos banderas nunca sincronizadas). Nuestras
dos sustituciones: `TIME` → `sim_time` (uniform), y `time_scale`/amplitud ∝ `wind_speed` (flamea
a 2-4 Hz con brisa, furiosamente en temporal). El mismo shader sirve para grímpola, toldos,
redes y cabos sueltos. Regla SoT: **al menos DOS indicadores redundantes siempre visibles**
(grímpola + comportamiento del agua).

**(e) La lluvia inclinada como veleta** (§1.3): el ángulo emerge solo de sumar el viento a la
velocidad de caída — con viento de 10 m/s ya viene a ~50°. Detalle que vende dirección gratis:
la lluvia AZOTA solo la cara de barlovento del puente (`dot(window_normal, wind_dir)` decide qué
cristales llevan gotas escurriendo).

**(f) Wind lines aéreas estilo Wind Waker/SoT** — fallback de legibilidad nocturna (el albedo
oscuro mata la mancha de cat's paws de noche): 4-8 ribbons (quad-strip de ~20 segmentos, alfa
recorriendo la cinta, ciclo 2-3 s) que aparecen solo en rachas fuertes. SoT las añadió
explícitamente porque "el jugador no puede sentir el viento". Prioridad baja.

### 4.3 El viento sobre el barco y el jugador

- **Barco**: deriva/abatimiento lateral (fuerza ∝ v²viento × área expuesta al rigidbody) —
  mantener rumbo en tormenta se vuelve trabajo activo del timonel. Mecánica coop gratis que
  refuerza la estación de TIMÓN.
- **Jugador**: `velocity += wind_vec · k · delta` en el CharacterBody3D — ~0,5-1,0 m/s² en furia
  8+ (andar contra el viento cuesta), picos de 1,5-2 m/s² solo con `gust01 > 0.8`. **JAMÁS tocar
  la cámara**: ni sway ni roll por viento — el feedback del golpe de racha es el desplazamiento
  real del cuerpo + el audio + (si acaso) el FOV kick ya presupuestado.
- **Objetos de cubierta**: `apply_central_force(wind_vec · área · c_d)` a los rigidbodies
  ligeros por encima de la borda — en furia alta la carga suelta se va sola por la borda:
  presión de supervivencia ("¡amarra las cajas!") derivada del mismo WindState (física del host).
- **Pesca** (conexión con el verbo del día 1): headwind acorta el lanzado y tailwind lo alarga
  (aceleración `wind_vec·k/masa` al aparejo en vuelo) — **el pescador experto aprende a lanzar
  en el lull entre rachas, y las rachas SE VEN venir en el agua** (§4.2a): mini-mecánica gratis
  que une viento y caña. El sedal (verlet 10-16 segmentos) se comba a sotavento con fuerza solo
  en los segmentos sobre el agua; la boya deriva al 2-3 % de la velocidad del viento (cifra
  náutica clásica) + corriente de ola que ya regala el Gerstner.

### 4.4 Modular el banco Gerstner con furia y viento SIN pops (el núcleo — riesgo técnico mayor)

El principio maestro de todas las fuentes serias (Tessendorf, Crest, GPU Gems): **las fases son
sagradas**. `k_i`, `ω_i` y `phase0_i` se congelan por semilla para siempre; furia y viento solo
modulan **amplitud y steepness**, que entran linealmente y no pueden hacer pop. `wave_proxy.gd`
**ya cumple esto** (banco congelado + JONSWAP re-repartiendo amplitudes) — la investigación lo
valida y añade lo que falta:

- **Regla de code review**: ningún parámetro dentro del `sin/cos` puede depender de furia ni de
  viento. (Es también la razón física por la que las rogue waves por re-faseo de la review del
  plan estaban mal: violan las fases sagradas.)
- **Viento que rola sin pops**: no se giran olas — se **re-pondera un banco de direcciones
  FIJAS** con una función de spreading (cos^2s de Mitsuyasu: s≈10 mar de viento, s≈70 swell;
  o Donelan-Banner con parámetro swell, Horvath 2015). Como D(θ−ψ) es C∞, si ψ(t) es suave las
  amplitudes crossfadean: "girar el mar" = morir unas olas y crecer otras. Con 12 slots se cubre
  bien ±90° alrededor del eje de viento de la sesión.
- **Giros grandes: reciclaje de slots** (GPU Gems cap. 1): la dirección de una ola SOLO cambia
  cuando su amplitud pasa por cero — envolvente de ventana por ciclo, parámetros nuevos de
  `hash(semilla, slot, nº_ciclo)`: sigue siendo puro y evaluable en cualquier t sin historia.
  Arquitectura sugerida: 4 bandas × 3 slots — SWELL (λ 150-400 m, direcciones fijas, s≈70, NO
  sigue al viento; el director puede alinearla con el tsunami), MEDIAS (λ 20-120 m, escalera fija
  ±75° re-ponderada), CORTA (λ 4-15 m, reciclaje T≈25-40 s persiguiendo al viento — coherente con
  la física: las cortas responden rápido, las largas no).
- **El director compromete el futuro**: en vez de escribir `furia_actual`, escribe **keyframes
  futuros de un spline C1** (`commit_fury(t_k, valor, pendiente)` con t_k ≥ sim_time + 90-120 s).
  `fury(t)` queda pura y evaluable en cualquier t — la consulta a futuro del tsunami sigue
  funcionando con furia variable. Y regala la telegrafía física real: la banda swell puede leer
  `furia_swell(t) = max fury(τ) para τ ∈ [t, t+180-300 s]` → **el jugador VE llegar las olas
  largas antes que la tormenta** (§3.3), la física del guion en vez de un efecto.
- **Cota de continuidad**: limitar `|dHs/dt| ≤ ~0,3 m/s` (25 m en ≥ 90 s) — acota también el
  "patinaje" horizontal por modulación de `Q_i·A_i`. (El `FURY_RATE_LIMIT = 0.4/s` actual de
  `Ocean` equivale a ~1 m/s de Hs en el tramo alto del dial: revisar al subir tiers.)
- **Qué NO copiar de los océanos FFT de Godot** (2Retr0/GodotOceanWaves como referencia visual):
  su espuma se ACUMULA en una textura con decay — es ESTADO, rompe la pureza y la consulta a
  futuro. La versión pura con el mismo look de persistencia: espuma = max del Jacobiano evaluado
  en 2-3 tiempos fijos (t, t−1 s, t−2 s). También documentan batidos entre bandas de λ cercanas:
  mantener ratios de λ no racionales simples (evitar λ_j = 2·λ_i exactos).
- **Tests headless** (GDScript puro sobre la consulta, sin GPU — compatible con el hallazgo 5 de
  la review del plan): (1) derivada acotada — `|∂h/∂t| ≤ Σ A_i·ω_i + |dA_i/dt|` es cota cerrada;
  un pop de fase la dispara órdenes de magnitud; guion adversarial: furia 0→10→0 en 60 s + rolada
  máxima + fronteras de ciclo de reciclaje + fronteras de keyframes. (2) pureza — evaluar
  `ocean(x, t=1234.5)` "en frío" vs tras reproducir la sesión: deben coincidir exacto (detecta
  estado acumulado, el enemigo nº 1).

---

## 5 · El audio del clima — la biblioteca real

> **Corrección de premisa (2026-08-23).** La versión original de esta sección daba por hecho que
> todo el audio del clima se sintetizaría, como el resto de `SfxLibrary`. **Ya no es así**: la
> lluvia y el viento son generados con ElevenLabs y los truenos son clips reales. Lo que sobrevivió
> intacto es la **arquitectura de mezcla** — separación por bandas, crossfade por furia, loops sin
> costura, ducking, determinismo — y de hecho fue lo que se usó para medir, filtrar y nivelar cada
> archivo. Las recetas de síntesis se conservan más abajo como referencia y plan B; el audio del
> **casco** (§6) y el chisporroteo pre-strike sí siguen siendo procedurales, porque no hay assets.

### La biblioteca (cerrada)

Todo en `game/audio/weather/`, 48 kHz estéreo 16-bit, verificado tras importar en Godot.

| Archivo | Tipo | Dur. | Origen | Proceso aplicado |
|---|---|---|---|---|
| `lluvia_calma_loop` | loop | 29,0 s | asset | wrap-crossfade 1 s |
| `lluvia_calma_2_loop` | loop | 29,5 s | ElevenLabs | HP 120 Hz, +4,2 dB, wrap 0,5 s |
| `lluvia_intensa_loop` | loop | 29,5 s | ElevenLabs | HP 160 Hz, −16,5 dB, wrap 0,5 s |
| `viento_temporal_loop` | loop | 23,0 s | ElevenLabs | HP 200 Hz, −16,3 dB, wrap 0,5 s |
| `trueno_seco` | one-shot | 4,0 s | asset | fades de borde |
| `trueno_cercano` | one-shot | 7,0 s | asset | fades de borde |
| `trueno_medio` | one-shot | 14,0 s | asset | recorte 0-14 s (6 s muertos) |
| `trueno_rodante` | one-shot | 16,3 s | asset | recorte 8,2-24,5 s (8 s muertos + cola) |

**Tres reglas que se aplicaron y hay que mantener al añadir cualquier archivo nuevo:**

1. **Referencia común −34,4 dB RMS** para todas las camas. El nivel de mezcla vive en la curva de
   furia, nunca horneado en el WAV: si no, el diseñador pelea contra el archivo.
2. **Paso-alto por capa** para que cada una respete su banda. Los cortes se eligieron midiendo, no
   por defecto: en los tres casos el filtro quitó 2-3 dB de sub moviendo el total ≤ 0,2 dB, o sea
   que se llevó el retumbe sin tocar el carácter.
3. **Longitudes coprimas**: lluvias en 29 s, viento en 23 s → el patrón combinado tarda ~11 min en
   repetirse. Cualquier cama nueva debe evitar múltiplos de esas.

### Perfil medido (dB por banda, a nivel de archivo)

| | <300 Hz | 300-1,5k | 1,5-4k | >4k |
|---|---|---|---|---|
| `viento_temporal` | −44,5 | **−38,4** | −44,8 | −48,5 |
| `lluvia_intensa` | −49,5 | **−41,4** | −41,9 | −42,2 |
| `lluvia_calma` | −61,7 | −48,0 | −41,9 | **−36,9** |

Lectura: **calma y viento no se tapan** (11,6 dB de separación en la banda alta). **Intensa y
viento sí comparten pico** en 300-1,5k, que además es la banda de la voz — por eso el cruce entre
ambas debe ser tardío y deliberado, no un fundido cualquiera.

### La curva de furia (hipótesis a tunear en el primer playtest)

El viento tiene **la pendiente más empinada de todas las capas**: casi ausente abajo, dominante
arriba. Esto no es estética — es lo que dispara la mecánica de enmascaramiento de voz (§3.5). Si
el viento se queda de fondo en el pico, el clímax pierde su instrumento sensorial principal.

| Furia | Lluvia calma | Lluvia intensa | Viento | Relación |
|---|---|---|---|---|
| 3 | −80 | −80 | −26 | solo un susurro |
| 5 | −12 | −80 | −18 | viento 6 dB debajo |
| 7 | −80 | −9 | −9 | **empatan — el cruce** |
| 9 | −80 | −4 | −2 | viento 2 dB encima |

El cruce en furia 7 coincide con el umbral donde DISENO ya declara que la pesca pasa a ser
"heroica" y el verbo cambia a sobrevivir: la mezcla y el diseño dicen lo mismo en el mismo punto.

### Variantes por semilla

Las dos lluvias calmas están al **mismo nivel y son intercambiables**: cuál suena se elige con
`hash(ocean_seed)`, así dos partidas del mismo mar no suenan idénticas sin romper el determinismo
(cada cliente deriva la misma variante de la misma semilla).

### Huecos declarados

- **Sin brisa**: el viento tiene un solo escalón. Por debajo de furia ~5 hay que reproducir el
  temporal muy bajo, que suena a temporal lejano, no a brisa. Si molesta, la brisa se deriva del
  mismo archivo con un lowpass (una brisa no es solo más floja: es más apagada), sin generar nada.
- **Sin silbido de jarcia**: se pierde la telegrafía de que el pitch suba antes de la racha (§4.2).
- **Sin cama de mar**: la banda 60-400 Hz está reservada y vacía. Es la capa que falta.

### Las recetas de síntesis (referencia y plan B)

Las canónicas son las de Farnell (*Designing Sound*, practicals 15/17/18, patches Pd publicados en
aspress.co.uk/sd/ — cada objeto Pd son 5-15 líneas de GDScript sobre `PackedFloat32Array`) y el
trueno de Fineberg (§2.6). Siguen siendo la vía para el audio de casco y para cualquier variante
que los assets no cubran.

- **LLUVIA** = cama de ruido bandpass ~2-6 kHz (el "shhh"; la energía real de la lluvia domina en
  agudos) + gotas como grains: sobre cubierta = ruido 1-2 kHz con envolvente exponencial de
  3-15 ms; **sobre el mar = seno corto con chirp ASCENDENTE 1,5→2,5 kHz** (el modelo físico de la
  burbuja — y la polaridad casa con nuestro `plip` existente). **3 intensidades pre-horneadas**
  (llovizna = banda estrecha aguda y pocas gotas; media = 30-80 gotas/s y banda hasta 2 kHz;
  aguacero = casi ruido blanco denso, los transientes se funden en textura) con **crossfade
  equal-power** por `fury01` en ventanas solapadas (0,15-0,5 / 0,4-0,8 / 0,7-1,0). Nunca parar
  los players (click): solo `volume_db`, con −80 dB como apagado.
- **VIENTO** = ruido blanco → bandpass con centro móvil. Números: rango útil del centro
  300-1500 Hz con 1000 Hz como punto dulce ("por encima suena sintético"); el centro sigue una
  curva Perlin lenta (0,1-0,5 Hz) horneada DENTRO del loop; rachas = envolvente 1/f; **amplitud y
  brillo suben JUNTOS** (la clave perceptual). 2-3 loops por banda de intensidad + crossfade.
- **SILBIDO DE JARCIA** = el mismo ruido con Q altísima (30-40) en 400-800 Hz, como capa SEPARADA
  que solo abre volumen desde furia ~5 — así la escalada no es solo "más fuerte": aparece un
  timbre nuevo. Física útil: tono eólico `f = St·v/d` (St≈0,2) — un obenque de 5 mm silba a
  ~600 Hz con 15 m/s y ~1,2 kHz con 30 — **el pitch del silbido ES información de viento**;
  modular `pitch_scale` ±10 % con `gust01`: el silbido que sube de tono medio segundo antes del
  golpe de racha es telegrafía sonora derivada del mismo ruido determinista que la mancha en el
  agua.
- **TRUENO**: §2.6.
- **CASCO** (del hueco mar↔barco, §6): crujido de madera = receta Farnell Practical 9 verificada
  — banco de 6 bandpass en paralelo (62,5/125/250/395/560/790 Hz, Q 1-3) excitado por tren de
  pulsos stick-slip; hornear 8-12 variantes de 1-2 s. Slam grave = thump (seno 85→35 Hz en
  120 ms + burst de ruido LP 400 Hz) excitando el mismo banco una octava abajo.

### Loops sin costura y mezcla

- **Wrap-around crossfade**: generar L+C segundos, mezclar los últimos C sobre los primeros C con
  ganancias equal-power (cos²/sin²) → loopea matemáticamente perfecto. **Aplicar DESPUÉS de los
  filtros** (los IIR tienen estado: filtrar tras cortar reabre la costura). Loops de 10-20 s con
  crossfade de 1-2 s son inaudibles como ciclo; usar longitudes coprimas para que el patrón
  combinado tarde minutos en repetirse (aplicado: lluvia 29 s, viento 23 s).
- **Cada capa dueña de su banda** (la separación es gratis: cada sonido ya nace de un bandpass):
  mar 60-400 Hz, viento 300-1100, silbido pico estrecho, lluvia 2-8 kHz, trueno = evento
  20 Hz-4 kHz. Ducking bajo el trueno: −4 a −6 dB en Weather+Sea durante el crack (~1 s, release
  2 s) por tween de `volume_db` (barato y determinista). Sidechain inverso para el slam de casco:
  el golpe SIEMPRE se lee (es información).
- **Cabina** = `AudioEffectLowPassFilter` de bus a ~600-800 Hz + −6..−10 dB con tween de 0,3 s al
  cruzar la puerta (el loop de gotas-en-techo SUBE dentro). Buses:
  `Master ← [Weather ← (Rain, Wind, Whistle), Sea, Thunder]` — extensión directa de
  `_setup_buses()`.
- **Reproducción**: los WAV se importan con loop detectado del chunk `smpl` (`loop_mode = Detect
  From WAV`, verificado) — nada que tocar en el dock. Los tres players de cama corren **siempre**;
  nunca se hace play/stop (produce click), solo se mueve `volume_db` con −80 dB como apagado, en
  ventanas solapadas equal-power. **Volúmenes de intensidad como función pura de
  `fury01(sim_time)`** — nada de estados acumulados: una reconexión reproduce la mezcla exacta, y
  en el late join hasta la fase del loop se restaura con `play(fmod(sim_time, loop_len))`.
  (Lo que sí se hornea al arrancar con `RandomNumberGenerator.seed = semilla_global` es el audio
  procedural que queda: casco y chisporroteo — mismo WAV bit a bit en todos los clientes.)

---

## 6 · Donde la tormenta se SIENTE: la interfaz mar↔barco

(Tercer hueco del crítico — en primera persona sobre un pesquero, esto es la tormenta.)

1. **Detector de slam por sondas** (el modelo "slamming force" de Kerner/Avalanche, sin
   triángulos): 4-8 Marker3D en proa/amuras/costados; por tick,
   `v_rel = v_vertical(sonda) − d/dt ocean_height(sonda)` (la derivada es analítica). Slam =
   sonda entra al agua con `v_rel` < umbral (~−2,5 m/s, escalado por furia); intensidad
   `clamp((|v_rel|−umbral)/rango)^1.5` × coseno con la normal de ola. Cooldown 0,4 s por sonda.
   **Alimenta TODO: spray, FOV kick, audio de slam, agua embarcada.** Es solo GDScript sobre la
   consulta existente.
2. **Spray estilizado**: burst one-shot de 12-24 partículas GORDAS de 2-3 tonos planos con alpha
   scissor (no blending) + escala cuantizada en escalones (`floor(scale·3)/3` — "saltea" de banda
   como todo el look), y un "sheet" de abanico por amura que escala 0→1 en 0,3 s scrolleando el
   MISMO patrón de espuma del océano. Wind Waker construye todo el contacto barco-agua así:
   geometría barata, cero simulación. **Cosmético local semillado por evento**
   (`hash(floor(sim_time·10), id_sonda)`): clientes bien sincronizados ven bursts casi idénticos
   gratis; lo único autoritativo es cuánta agua embarcó.
3. **Green water sin fluidos**: evento de embarque = `ocean_height(punto_borda) >
   altura_borda + margen` en 4-6 puntos (puro, en el host). Visual = plano de agua de cubierta
   (QuadMesh con el shader del océano en modo "charco": mismas bandas, sin Gerstner) cuya
   inclinación copia pitch/roll del barco **con retardo de ~0,3 s** (el slosh barato: el agua
   persigue la inclinación, nunca la iguala) + goteo por los imbornales del lado bajo. La
   shallow-water 2D de Still Wakes the Deep queda explícitamente FUERA: su valor no justifica el
   coste en un look de bandas.
4. **El bucle de achique** (SoT + Sailwind): `water_level` 0..1 — entradas: lluvia (goteo) +
   olas sobre borda (+0,03-0,08 por ola, el grueso) + vías por daño; salidas: cubo (−0,04 por
   cubada de ~1,5 s, exige ir a la borda a vaciar → te expone a la siguiente ola), bomba fija
   (−0,02/s con alguien accionándola), imbornales (solo cubierta, no bodega). Umbrales: > 0,4 el
   barco responde peor (masa añadida → más slams), > 0,75 alarma, 1,0 hundimiento. **Con furia
   8+, 2 jugadores achicando deben empatar con el mar: el punto de equilibrio ES el dial de
   dificultad**, y se calcula en frío porque el embarque medio por ola es función de (furia,
   rumbo). Réplica: un float a ~4 Hz + bitmask de agujeros + eventos one-shot
   `ola_sobre_borda(intensidad, lado)`. Sailwind añade el telégrafo: el SONIDO de "water ingress"
   avisa antes que cualquier UI.
5. **Confort sin horizonte** (estudio comparativo arXiv 2103.05200: el "rest frame" estable
   mitiga tanto como la viñeta PERO sin perder información — y aquí leer la ola importa):
   el interior del pesquero ES el rest frame (en tormenta, la jugabilidad ya empuja a la
   timonera); **falso horizonte diegético**: lámpara de cardán y compás de bitácora nivelados
   respecto al MUNDO (rotación de un prop, no de cámara) — un horizonte de bolsillo que la niebla
   no puede tapar; y la viñeta existente escalada con |velocidad angular del barco|, no con furia
   (viñeta cuando hay estímulo vestibular, pantalla limpia cuando no).

---

## 7 · Red y determinismo: las reglas duras

- **Los tres patrones de fallo documentados** (No Man's Sky: cada jugador su clima; Conan Exiles:
  clientes juntos ven climas distintos; Terraria: spawns de lluvia sin lluvia visible en el
  join): (1) clima tirado con RNG local, (2) flag replicado no aplicado al late join, (3) capa
  gameplay y capa visual leyendo relojes distintos. Nuestra arquitectura los mata de raíz, PERO:
  **prohibir `randf()`/`randi()` sin semilla en todo código de mundo** (lint: grep en
  directores/efectos — `SfxLibrary.play_varied` puede seguir usando randf: es presión sonora
  local).
- **El reloj de interpolación no toca el clima**: mar, cielo, rayos y clima derivan de `sim_time`
  — idénticos sin retraso. Solo los avatares remotos van ~100-200 ms detrás (Gaffer: 150 ms a
  30 snapshots/s). Mantener DOS tiempos explícitos: `sim_time` (mundo) y
  `remote_render_time = sim_time − interp_delay` (avatares); efectos anclados a un avatar remoto
  (sus salpicaduras, el rayo que "le" cae) se evalúan en el retrasado. Esto acota el hallazgo 3
  de la review del plan: la costura jugador↔barco↔red del clima ya está resuelta por
  construcción.
- **`sim_time` se DESLIZA, jamás se corrige a saltos**: un step teletransporta el océano entero.
  Slew limitado a ±2 % de dilatación; step solo si el error > ~250 ms, y entonces taparlo (negro
  o justo tras un impacto). Replicar el reloj como TICK entero (u32 a 120 Hz físico) y derivar
  `sim_time = tick/120.0` en doble precisión — sin drift de sumar deltas.
- **Precisión float en el shader** (criterio propio): tras horas de partida `sim_time` grande
  degrada las funciones de ola en float32 — pasar al shader `fmod(sim_time, T_wrap)` con un
  período común grande, aplicando el MISMO wrap en la consulta CPU.
- **Late join = evaluar, nunca reproducir** (patrón vorixo/Unreal; el anti-patrón es el clima de
  Minecraft apareciendo como switch): recibir seed + tick → esperar convergencia del reloj →
  evaluar TODO de golpe (furia, acto, fog, fase día/noche, clima, y la fase de los loops de
  audio). **Regla que esto impone: el director se escribe como `evaluate(t)` puro — JAMÁS tweens
  ni corrutinas que acumulan estado.** El `move_toward` de `fog_density` en
  `TsunamiDirector._update_atmosphere()` es exactamente "la rampa" que un late joiner no puede
  reproducir: migrarlo a función de t. Primer frame tras el join: setear valores directos, sin
  interpolar desde defaults.
- **QA automatizable**: (1) join a mitad de TORMENTA comparando `hash(weather_state(t))` entre
  peers; (2) dos clientes logueando el mismo slot-id/posición del mismo rayo (aunque su retardo
  de trueno difiera); (3) overlay de debug con `(tick, hash(weather_state))` por peer — detectar
  el desync y mostrarlo es mejor que negarlo (precedente DST).

---

## 8 · Plan de implementación priorizado

Ordenado por (impacto en "el mar es el antagonista") / coste. Cada fase es demostrable por
separado con el dial de furia existente, y el TsunamiDirector la orquesta sin código nuevo.

**Fase A — el shader cuenta la tormenta (una tarde, transforma el juego): ✅ HECHA (2026-08-23)**
1. ✅ Uniforms `rain01`, `gust01`, `wind_dir`, `wind_drift` (por `Ocean.apply_frame_to_material`,
   la misma tubería que `ocean_time`; `lightning01` queda para la fase C, que es quien lo usa).
2. ✅ En `ocean_surface.gdshader`: specular apagado Y encogido con `rain01`; detail gradient
   ×0,4 bajo lluvia; cat's paws (resta al escalar de bandas + eriza el detalle, gate furia
   0,5-5,5 × racha); estrías anisótropas 16:1 en el patrón de espuma antes de cuantizar (gate
   furia 5+). ❌ El moteado de "chispazos" en albedo se probó y se RETIRÓ por feedback del
   playtest: leía como puntos sin sentido, no como agua picada — la lluvia sobre el mar la
   cuentan el specular muerto, el detalle planchado, la niebla y las gotas cayendo.
3. ✅ Niebla: densidad +150 %·rain01 en el director; desaturación del color en `DayNightCycle`
   (el color es SU perilla — cada uno la suya). ⚠️ La rampa sigue siendo `move_toward` sobre el
   tick de física: la migración a `evaluate(t)` puro queda para la fase D, con el parte
   meteorológico (la niebla es uno de sus canales).
4. ✅ Viento dentro de `Ocean` (misma semilla/reloj/pausa): `gust01_at(t)` puro por suma de
   senos (consultable a futuro), tabla Beaufort `WIND_MS`, `wind_dir_vector()` con oscilación
   lenta, deriva acumulada `wind_drift` (estado integrado como la furia — pura en fase D).
5. ✅ (adelantado de la fase B) **Gotas visibles**: `game/world/rain_particles.gd`
   (`RainParticles3D` en toybox y tsunami) — losa de emisión sobre la cámara según el checklist
   de §1.3: trazos alineados a velocidad, viento en `gravity`, `amount_ratio` como dial,
   `visibility_aabb` generosa, sin heredar rotación de cámara. **El trazo es semitransparente
   con puntas difuminadas** (textura horneada al arrancar), no opaco de borde duro: en vídeo
   real la lluvia es mezcla fraccional con el fondo (MSR-TR-2006-102, Garg-Nayar) y la primera
   versión opaca leía como barras molestas — feedback del playtest. **Brillo acoplado a la luz
   ambiente** (unshaded modulado por frame desde el Environment): de noche baja a un piso tenue.
   Ni unshaded fijo (quemaba de noche) ni material sombreado (invierte la polaridad contra el
   cielo: la gota real refracta el cielo entero, no un sol puntual) — la historia completa está
   comentada en `rain_particles.gd` para que nadie repita el ciclo. **Refugio**: caja
   `GPUParticlesCollisionBox3D` sobre el volumen de la cabina en `fishing_boat.tscn` +
   `COLLISION_HIDE_ON_CONTACT`: dentro no llueve (verificado con captura). Pendiente de
   fase B: cortina lejana y splashes.
   Extra: la lluvia es INDEPENDIENTE de la furia (`rain_level`, ver §1.2) + `rain_scale` por
   acto (la RETIRADA corta la lluvia), deslizadores de lluvia y horario en el HUD debug (panel
   con scroll), `tests/weather_tests.tscn` (21 checks) y `tests/capture_weather.tscn` para
   revisar el look con GPU real.

**Fase B — lluvia y viento audibles y tangibles (la semana del feel):**
5. ✅ (2026-08-23) `WeatherAudio` (autoload, `game/audio/weather_audio.gd`): 3 camas siempre
   corriendo con fase anclada a `sim_time` (late join = misma fase), crossfade equal-power —
   la lluvia por `rain01` (calma→intensa con cruce 0,4-0,85), el viento por `wind_speed()` con
   la racha respirando ±2 dB; ducking −6 dB bajo el trueno con release de 2 s; interior de
   cabina = LPF 750 Hz + −9 dB decidido contra el MISMO volumen que corta las gotas
   (`RainShelterCabin`: un solo techo para ojos y oídos); variante de calma por semilla.
   Truenos: `play_thunder(distancia)` elige clip por distancia (cerca=crack, lejos=rodante) —
   tecla T del HUD para probar; el scheduling determinista es de la fase C.
6. ✅ Cortina cilíndrica (`rain_curtain.gd/.gdshader`): trazos por columna con fase y
   velocidad propias, franja del horizonte, atenuación radial en pantalla (anti-mareo §1.5),
   brillo acoplado al ambiente como las gotas. La estructura admite N capas (parallax estilo
   Remember Me) pero **quedó una sola a 225 m**: la capa cercana de 135 m se probó y se
   descartó — a esa distancia leía como superficie, no como lluvia. Su velocidad (1,60) es una
   trampa deliberada: lo físico (~2 °/s a esa distancia) lee como niebla.
   ✅ **Anillos de impacto** (`rain_splashes.gd/.gdshader`): planos que se clavan en la ola
   evaluando la MISMA suma Gerstner en su vertex shader, vértice a vértice (así el aro se curva
   con la ola en vez de atravesarla) con `surface_lift` para no salir como media luna —
   `depth_draw_never` no escribe profundidad pero sí la comprueba. Aros de borde duro que
   crecen y se apagan; anillos y no puntos, que fue lo que el playtest rechazó.
7. ⏳ APLAZADO deliberadamente: banderas/grímpola y empuje de viento a jugador/objetos tocan
   `player.gd` y el barco visual — ambos con trabajo SIN COMMITEAR de otra sesión (rework de
   rig/bodega). Entrar ahí ahora es pisar a un compañero en caliente.
8. ⏳ Spray de proa: la señal `slammed` del barco ya existe (F1) — falta el burst + sheet.
   ⚠️ El audio de casco (crujidos/slams) ya NO se sintetiza: regla 10 del repo (ElevenLabs).
   Las recetas Farnell de §6 quedan como espec de referencia para los prompts.

**Fase C — el cielo y los rayos (el drama):**
9. ✅ (2026-08-23) **Sky shader propio** (`game/world/sky.gdshader`), con tres pases:
   `AT_CUBEMAP_PASS` solo baja frecuencia (si el fbm fino entra al cubemap de radiancia, el
   scroll de las nubes hace **hervir la luz ambiente de toda la escena**); `use_half_res_pass`
   para el fbm de nubes; y el pase principal componiendo gradiente + astros + nubes + destello.
   Nubes de 4 octavas en dos capas a escalas y velocidades distintas (truco Wind Waker), con
   cobertura y **dureza de borde** crecientes con la furia. `DayNightCycle` migrado: escribe los
   mismos nombres de uniform que usaba `ProceduralSkyMaterial`, así que el perfil `.tres` no
   cambió; sigue soportando el material viejo por si alguna escena lo usa.
   **El disparador fue un bug**: `ProceduralSkyMaterial` pinta un disco de sol **por cada
   `DirectionalLight3D` de la escena**, así que al añadir la luz del rayo apareció un tercer
   "sol" difuso flotando en el cielo. Ahora los astros se dibujan desde direcciones explícitas
   que pasa `DayNightCycle`, y hay test que exige `sky_mode = LIGHT_ONLY` en toda luz que no sea
   Sol o Luna: añadir luces al mundo no puede volver a ensuciar el cielo.
   Dos calibraciones que salieron de mirar capturas: (a) el cielo se cuantiza a **40 bandas con
   dither**, no a 14 como el agua — el mar cuantiza la *iluminación* de una superficie con
   normales y ahí el escalón es estilo, pero el cielo es un gradiente casi plano estirado por
   media pantalla y a 14 salían **contornos de posterización**; (b) las nubes se apagan a
   `EYEDIR.y < 0.38`, porque la proyección al plano se dispara cerca del horizonte y el ruido
   aliaseaba en churretes oscuros.
   ⏳ Pendiente: `front01` (el frente de tormenta direccional) está implementado pero a 0 —
   lo conectará el director dramático en fase D.
10. ✅ (2026-08-23) `LightningDirector` (`game/world/lightning_director.gd`): el tiempo se
    parte en slots de 6 s y un hash de (semilla, slot) decide si hay rayo, tipo, azimut,
    distancia y pulsos — mismo rayo en los 6 clientes sin replicar un byte, y **consultable a
    futuro** (`seconds_to_next_strike()`, la puerta para que el director dramático reserve un
    rayo en fase D). Envolvente multi-pulso (3 return strokes a 45 ms) con cola.
    **El destello es promoción de banda**: un `global uniform lightning01` desplaza los
    umbrales de la rampa cuantizada del agua (§2.1) — nada de bloom, y así el delta de
    luminancia es discreto y auditable. Canales: uniform global + `DirectionalLight3D`
    dedicada (aparte del sol, que lo escribe el ciclo día/noche) + `background_energy_multiplier`
    (la única propiedad del Environment que nadie más toca).
    Bolt por midpoint displacement horneado al arrancar (4 variantes), revelado de arriba abajo
    en 100 ms y afterglow **en escalones discretos**, con `step()` y `blend_mix` — un rayo
    aditivo es un glow y este proyecto pinta plano.
    Truenos de §5 elegidos por distancia con retardo `d/343` real.
    **Fotosensibilidad garantizada por construcción** (§2.5): ≤3 pulsos por evento y margen
    dentro del slot que asegura ≥2,4 s entre eventos; hay test que muestrea 5 min de tormenta
    a furia 10, cuenta los picos de la envolvente y verifica que nunca hay más de 3 en una
    ventana de 1 s. Toggle "Reducir destellos" (jamás "apto para epilepsia") y botones de
    rayo/trueno por distancia en el HUD debug (teclas R y T).
    **Revisión adversarial** (12 agentes: 4 lentes × verificación escéptica; 19 hallazgos
    confirmados de 29). Lo que cambió por ella:
    - **La furia entra CUANTIZADA a pasos de 0,5 y el slot se congela al empezar.** `Ocean.fury`
      no es un valor replicado: es estado integrado local (rate limit 0,4/s) que el host gotea a
      10 Hz, así que entre paquetes las máquinas difieren hasta ~0,04 — y leyéndola en vivo eso
      volteaba decisiones **booleanas** (el rayo existía en una pantalla y no en la otra). Test
      que mide el residuo real en vez de fingir que es cero. *Limitación declarada*: esto lo
      acota, no lo elimina; la solución definitiva es el parte meteorológico de la fase D.
    - **El cruce a "tormenta encima" es continuo.** Era un escalón duro en furia 6 entre dos
      rangos de distancia **disjuntos** (1400-3000 m y 180-2200 m): dos máquinas a un lado y otro
      daban, para el mismo destello, truenos separados varios segundos y con clip distinto. El
      salto máximo pasó de ~1400 m a <500 m.
    - **La luz del destello no ilumina el agua** (`light_cull_mask` excluye la capa 2, que ahora
      es la del `OceanSurface`). El `light()` del océano suma `ambient_level` de forma **plana**
      mire donde mire la normal, así que la luz del rayo borraba exactamente las bandas que el
      destello acababa de promocionar. Visible en las capturas: antes el mar se lavaba de blanco
      uniforme, ahora conserva su estructura.
    - **`force_strike()` consulta la secuencia natural**, no solo el forzado anterior:
      `intensity_at()` combina ambas capas con `maxf`, así que un rayo de debug encima de uno
      programado apilaba 3+3 pulsos en menos de un segundo — un agujero real en el techo
      fotosensible. (Y el test que lo cubría era **vacío**: pasaba igual con y sin la guarda,
      porque no movía el reloj.)
    - Menores: la rama del rayo forzado no tenía cota inferior de edad (con el reloj hacia atrás
      secuestraba el canal del bolt para siempre); el trueno forzado usaba `create_timer`, que
      corre en tiempo real e ignora la pausa; `_slots`/`_fired` no se limpiaban al cambiar de
      semilla ni al saltar el reloj (las dos cosas pasan juntas al unirse a una partida) y se
      podaban solo por abajo, así que las claves del futuro eran inmortales.
    - Ya estaba bien de antes: el trueno sale del rayo **congelado al verlo** y `_exit_tree()`
      devuelve uniform, cielo y luz a su sitio (si el director moría en pleno destello, el mundo
      quedaba quemado para siempre).

**Fase D — el clima como gameplay (cuando exista la bomba/bodega de F1-F2):**
11. `water_level` + embarque por borda + achique (el verbo ya diseñado en DISENO).
    ✅ **Hecho (24-ago-2026)**, por la sesión paralela: el barco embarca agua por mar gruesa,
    lluvia, olas sobre la borda y celdas enterradas, y se hunde; la bomba manual achica de verdad
    con un ciclo de dos tiempos (mantener el clic chupa a una cámara, soltarlo escupe al mar), y
    el agua de la cámara sigue contando a bordo hasta que se escupe. `manual_pump_tests` (100),
    `bomba_tests`, `agua_tests`, `docs/BOMBA_MANUAL.md`. *(Esta línea decía «la bomba todavía no
    mueve agua»; quedó rancia el mismo día.)*
12. Rayo-mecánica (mástil, metal en mano, chisporroteo) — requiere furia ≥ 6 y el canal de
    eventos del host. **Parcial (24-ago-2026).**

    ✅ **El «lightning jump» hecho**, y lo destrabó el parte. La cadencia de rayos de un slot ya
    no la manda la furia de ahí sino `max(furia_aquí, 0,75 · furia_swell(t₀, 15 min))` — o sea la
    tormenta que VIENE. Lo bonito es que la imagen correcta sale sin una línea especial: la
    distancia y el `bolt` siguen calculándose con la furia LOCAL, que todavía es baja, así que los
    rayos anticipados caen todos en el rango lejano y **ninguno tiene geometría**. Resplandor de
    nube mudo en el horizonte con el mar planchado, que es exactamente lo que describe la
    investigación (§2.4). Sin parte, `furia_swell` devuelve la furia actual, el salto es cero y la
    cadencia es la de siempre: los dos carriles otra vez. Tests en `parte_tests`.

    ⛔ **Lo demás sigue bloqueado, y no por diseño sino por piezas que no existen**: el barco no
    tiene mástil (buscado: cero nodos), no hay concepto de «metal» en `Portable3D`, y no hay
    sistema de daño ni de reparación. Además `player.gd`, `fishing_boat.tscn` y `portador.gd` son
    justo los archivos que la sesión paralela tiene abiertos. Lo que falta es sobre todo trabajo de
    ASSET y de sistema nuevo, no de clima.
13. Enmascaramiento del bus de voz por furia. **Parcial (24-ago-2026): la mecánica está, el
    transporte no.** Lo que ya existe y se puede ajustar hoy es `VozModel` (puro, con
    `tests/voz_tests.tscn`) + `VozProximidad`, un `AudioStreamPlayer3D` que encoge su radio y
    cierra el paso-bajo del bus `Voz` con el ruido ambiente. **El ruido NO es una curva propia**:
    es `WeatherAudio.ruido01()`, la mezcla equal-power de las camas que ya suenan — dos curvas
    que dicen lo mismo se separan en cuanto alguien afina una, y la voz se perdería sin que el
    jugador oyera nada raro. El refugio baja el ruido (`alivio_interior`), o sea que la cabina
    vuelve a ser un sitio donde se habla. Balance en `resources/audio/voz_proximidad.tres`.
    ⚠️ Queda el transporte de voz (two-voip, fase R2): hoy no hay stream que meterle, así que
    la mecánica se prueba con un bucle cualquiera de voz de prueba.
    ⚠️ Y este doc y `PLAN.md` no decían lo mismo: aquí «~40 m en F0 → 8-10 m en F9», allí «30 m
    → 3 m». Se toman los de aquí por ser conclusión de investigación y no eslogan; el número
    definitivo sale del playtest y se mueve desde el `.tres`.
14. ✅ **El parte meteorológico** (24-ago-2026). Canales comprometidos por adelantado
    (furia, lluvia, rumbo del frente) + `furia_swell` lookahead. Quedan fuera las celdas de
    chubasco locales y la niebla del director. Ver el diseño y el registro de obra abajo.

### 14 · El **Parte Meteorológico** — ✅ implementado (24-ago-2026)

> `addons/ocean/clima/parte_meteorologico.gd` (la curva) y `generador_parte.gd` (quien la
> redacta), `tests/parte_tests.tscn` (97 comprobaciones). Lo que sigue es el diseño tal como se
> fijó; al final, **lo que se aprendió construyéndolo** — que no fue poco.

> **Sobre el nombre.** Nació como `FuryTrack`, que cubría solo la furia. Se renombra al término
> que DISENO ya usaba —«parte meteorológico como mutador consultable»— porque el alcance real son
> varios canales, y no conviene que existan dos palabras para la misma cosa.

Convertir el clima de *valores que se escriben cada frame* en **guion escrito por adelantado**: el
director publica keyframes futuros y cada canal pasa a ser una función pura `canal(t)`, evaluable
en cualquier instante. Spline Hermite **C1** — con C0 se ve el quiebro de aceleración en el mar.

#### La regla que ordena todo (decisión de diseño, 2026-08-24)

> **Si sube la furia NO tiene por qué llover. Si sube la lluvia SÍ tiene que subir la furia.**

Es la causalidad real del mar, y de ella sale toda la estructura:

- **El mar viaja; la lluvia no.** Una tormenta a 300 km manda su mar de fondo pero no su agua. Por
  eso furia 8 con cielo seco es un estado legítimo: ese mar es de OTRO lado, o de hace horas.
- **El chubasco encima siempre azota el mar local.** No existe el diluvio sobre mar planchado: la
  celda convectiva que descarga agua descarga viento.

Formalmente: la lluvia impone un **piso** a la furia, `furia(t) ≥ piso(lluvia(t))`, y nunca al
revés. No es un acoplamiento —la lluvia no empuja la furia— sino una **restricción sobre lo que el
generador tiene permitido escribir**. `Ocean` sigue con los canales independientes: la regla vive
en quien redacta el parte, no en quien lo ejecuta.

Y lo que compra es **legibilidad**: el jugador razona como un pescador. Empieza a llover → el mar
viene detrás, garantizado. Mar enorme con cielo abierto → la tormenta está en otra parte, o ya
pasó. El clima deja de ser decorado y pasa a ser información accionable.

**El piso**, atado a `DOUGLAS_HS` y a las bandas que ya usa el audio (los beds cruzan CALM→HEAVY
entre 0,30 y 0,40):

| lluvia | qué es | piso de furia | Hs mínimo |
|---|---|---|---|
| 0,3 | llovizna | 1,8 | ~0,35 m |
| 0,6 | lluvia franca | 3,6 | ~1,9 m |
| 1,0 | diluvio | 6,0 | 6 m |

`piso = 6·lluvia`, lineal, tal cual lo hace `GeneradorParte.piso_furia()`. *(Esta tabla decía 2 y 4
para las dos primeras filas — los redondeos «bonitos» del diseño, no lo que el código calcula.
Corregido: un doc que redondea a favor es un doc que miente.)* La curva fina es tuning de playtest. Lo que importa es que
**diluvio ⇒ furia ≥ 6**, que es justo donde el cruce a «tormenta encima» de los rayos
(`near = (furia−5)/2.5`) ya está activo: el diluvio trae rayos sin tocar esa fórmula.

#### Los canales, y cuánta libertad tiene cada uno

| canal | libertad | quién lo manda |
|---|---|---|
| **furia** | muy guionada | sierra por actos + techo del caladero + cota de pendiente en Hs |
| **lluvia** | suelta, sembrada | dados por acto, encajados DENTRO de las jorobas de furia que alcanzan el piso |
| **rumbo del frente** | sembrado | alimenta `front01`/`front_dir` del cielo (implementados, hoy a 0) |
| **niebla** | más adelante | hoy es un `move_toward` irreproducible (§7) |

**El orden de generación es lo que garantiza el invariante:** primero se escribe la furia (la
sierra por actos, el techo del caladero, la cota en Hs); después se encaja la lluvia dentro de las
jorobas que le dan piso suficiente. El invariante queda cumplido **por construcción** —el mismo
principio que el techo fotosensible de los rayos— y se testea como propiedad del generador, no
del `Ocean`.

La envolvente de la lluvia es **asimétrica** respecto de su joroba de furia: entra tarde y sale
temprano. El mar de fondo la precede (§3.3, ya escrito) y le sobrevive — cubierta mojada, cielo
abriendo, mar todavía grande. El beat de «ya pasó» sale gratis.

#### De dónde salen los dados

`hash(semilla_diaria, caladero, acto)`: si llueve en este acto, cuándo dentro de él, cuánto y de
qué rumbo. Derivado, **nunca** `randf()` en vivo — es la regla 4 del repo y lo que hace posible la
semilla diaria de DISENO («todos los grupos del mundo pescan el mismo mar ese día»). El precedente
ya funciona: los rayos salen enteros de `hash(semilla, slot)`, parecen azar puro, son idénticos en
seis pantallas sin replicar un byte y encima son consultables a futuro.

El host solo transmite **cuándo arranca cada acto** —los hitos de cuota son timing de jugadores,
no se pueden derivar—; todo lo demás lo calcula cada máquina.

Dos consecuencias que caen solas:

1. **El caladero promete también el cielo.** BAHÍA (techo 3) no puede pasar de llovizna; el
   diluvio solo existe en LA FOSA y AGUAS NEGRAS. «La furia prometida es la furia entregada» se
   extiende a la lluvia sin una línea extra.
2. **La furia no es azar, y eso es deliberado.** DISENO: sube «por actos e hitos de cuota, nunca
   por reloj crudo», y «jamás se modula por rendimiento ni por valor de carga». La forma la pone
   el director (la sierra de Left 4 Dead); la semilla decide los detalles DENTRO de esa forma.

**Los tres problemas que paga** (los tres ya medidos en el repo, no hipotéticos):

1. **Los rayos divergen entre máquinas.** `Ocean.fury` es estado integrado local (rate limit
   0,4/s) que el host gotea a 10 Hz; entre paquetes las máquinas difieren ~0,04 y eso volteaba
   decisiones booleanas. Está mitigado cuantizando a pasos de 0,5 (ver §2 y el encabezado de
   `lightning_director.gd`), y ahí mismo queda declarado que es un parche: con `fury(t)` el
   sampler evalúa la furia en el `t0` del slot y el rayo es idéntico sin depender de la red.
2. **La consulta al futuro del mar de VIENTO es hoy una mentira piadosa.** Para el tsunami la
   promesa se cumple entera (la capa de eventos es analítica en t), pero
   `Ocean.get_height_at(pos, t+60)` evalúa las Gerstner con las amplitudes **de ahora**
   (`_amp` en `wave_proxy.gd`): si la furia sube en esos 60 s, la respuesta es incorrecta. Con
   `A_i(t)` derivada del track, la tesis del proyecto pasa a ser cierta sin asteriscos.
3. **La rampa meteorológica real (§3.3) es imposible sin él.** «El mar de fondo llega primero»
   exige saber qué furia VA a haber: la banda larga lee `furia_swell(t) = max fury(τ)` para
   τ ∈ [t, t+180-300 s]. La telegrafía deja de ser un efecto y pasa a ser física del guion.

**El contrato:** el director **nunca** edita keyframes con `t < sim_time + horizonte` (~90-120 s).
El pasado y el futuro cercano son inmutables — y esa restricción es justo lo que hace confiable la
consulta. Cuesta latencia dramática, que es también el tiempo que las olas largas necesitan para
llegar antes.

**Las tres correcciones al plan (revisión 2026-08-23) — sin ellas el refactor rompe cosas:**

- **DOS CARRILES, no uno.** CLAUDE.md declara sagrada la perilla de furia del HUD en F1 («en
  manos de alguien haciendo de dios ES la herramienta de validación del juego»). El horizonte
  inmutable la mataría: mover el dial y que el mar tarde 90 s en enterarse la vuelve inútil. Tiene
  que convivir un **carril manual/inmediato** (toybox y debug, lo que hoy es
  `set_fury_immediate`) con el **guion comprometido** (escenas dirigidas y red). Es el mismo
  patrón que ya usa `LightningDirector.force_strike()`: la capa forzada se suma encima sin
  romper la determinista.
- **La cota de pendiente va en Hs, NO en furia.** El límite de la investigación es
  |dHs/dt| ≤ ~0,3 m/s (por el patinaje lateral que produce modular `Q_i·A_i`). El
  `FURY_RATE_LIMIT` actual de 0,4 furia/s equivale, en el peor tramo del dial (de furia 9 a 10 hay
  **7 m** de Hs), a **2,8 m/s** — o sea **9,3 veces el límite**; incluso en el tramo 8→9 (4 m) son
  1,6 m/s, más de cinco veces. El track no puede heredar el rate limit tal cual: la cota se
  expresa en metros y se traduce a pendiente de furia según el tramo, que es no lineal por
  construcción (`DOUGLAS_HS` interpola en Hs justamente porque Hs escala como U²).
- **El alcance es mayor que la furia.** `rain01` (rampa integrada) y `_wind_drift` (acumulador de
  la deriva del viento sobre el agua) también son estado integrado — está anotado en `ocean.gd`
  como «pura en fase D». `_wind_drift` pasa a ser la **integral cerrada** del spline de viento
  (integrar un polinomio cúbico es analítico). La lluvia **ya tiene decisión**: es un canal
  comprometido más, con el piso de arriba como restricción de generación.

**Detalle técnico menor pero real:** `max fury(τ)` sobre ventana deslizante es continuo pero tiene
quiebros de derivada cuando cambia el argmax. Aceptable, pero el test de continuidad (el bound
analítico de §4.4) debe incluir ese caso.

**Lo que destraba de una:** rayos idénticos en red sin el parche de cuantización; `front01` del
cielo (el frente de tormenta, implementado y a 0 porque necesita saber de dónde y cuándo viene);
y la niebla del `TsunamiDirector`, que hoy es un `move_toward` — una rampa que un jugador que se
une a mitad de partida **no puede reproducir** (§7).

**Decisión abierta — ¿el rayo cuelga de la lluvia?** Hoy el gate del rayo es solo la furia, así
que furia 8 seca tiene tormenta eléctrica. En la realidad el rayo es hijo de la nube convectiva,
no del oleaje: mar de fondo bajo cielo abierto no truena jamás. **Recomendado**: mover el gate al
canal de lluvia (rayos si `lluvia > ~0,5`), que por el piso ya garantiza la furia necesaria, así
que la fórmula actual casi no cambia. Suma una inferencia más al pescador («veo rayos → hay
chubasco → se viene el mar») y deja la furia 8 seca sin truenos, que es lo correcto: su sonido es
el viento aullando, y ese bed ya escala con la furia.

**El coste honesto:** toca `Ocean`, `wave_proxy` (las amplitudes pasan a depender de t), el
`TsunamiDirector` entero y el campo de furia del paquete de red. Es refactor de fontanería: el día
que termine no se ve nada nuevo en pantalla.

Lo que parecía su peor consecuencia —**el director pierde la reacción instantánea**, un hito de
cuota no puede subir la furia YA— resulta ser la feature. El hito compromete la furia a
`ahora + horizonte`, y esos 90-120 s son el mar RESPONDIENDO: el mar de fondo llegando antes que
el viento, que es exactamente la rampa de §3.3. La telegrafía no puede mentir porque el guion ya
está escrito.

#### Lo que se aprendió construyéndolo

Cinco cosas que el plan no anticipaba. Las dos primeras son errores que el plan **tenía dentro**:

1. **La cota de pendiente necesitaba DOS factores, no uno.** El plan decía «acotar |dHs/dt| ≤ 0,3».
   Acotar la pendiente *media* de cada tramo deja pasar picos por partida doble: un tramo con
   pendiente 0 en los extremos es un smoothstep, que alcanza **1,5×** su media en el punto medio;
   y `dHs/dfuria` **no es constante dentro del tramo** — de furia 8 a 9 hay 4 m y de 9 a 10 hay 7,
   así que un tramo 8→10 acelera justo al final. El tiempo mínimo real es
   `1,5 · Δfuria · max(dHs/dfuria en el rango) / 0,3`. Con la fórmula ingenua el test de pendiente
   sale en rojo; está en `GeneradorParte._tiempo_minimo` con las dos razones escritas.
2. **En red, la perilla de dios tiene que apagar el guion para TODOS.** El plan decía «dos
   carriles» y eso, tal cual, produce una divergencia silenciosa de manual: el host mueve el dial,
   su parte se suspende, empieza a gotear su furia por el cable... y los clientes la **ignoran**
   porque siguen con guion en vigor. Seis pantallas con mares distintos y cero errores en consola.
   `Debug.FURIA`/`FURIA_YA` apagan el parte en toda la tripulación antes de tocar nada.
3. **`set_fury_red` tiene que ignorar el cable cuando hay guion.** No es solo redundante: el goteo
   de 10 Hz mete un escalón entre paquetes justo en la curva que existe para no tener escalones.
4. **El parte va en el paquete de bienvenida, y no es opcional.** Quien se une sin guion cae al
   carril manual, donde los rayos se deciden con la furia *cuantizada* en vez de con el spline —
   o sea que vería una tormenta eléctrica **distinta** de la de sus compañeros. Se manda la curva
   entera (~medio kB, una vez) y no la receta «semilla + techo», porque `generar_parte()` la
   escribe desde la furia y el reloj de quien la pide, y esos dos números difieren entre máquinas:
   la misma receta daría partes parecidos pero **no iguales**.
5. **Hacer honesto `get_height_at()` salió barato** — y solo se supo mirando. Fuera de los tests no
   lo llama nadie en producción, así que re-espectrar el banco de olas con la furia del instante
   consultado no toca ningún camino caliente. Va sobre un **proxy aparte**, generado con la misma
   semilla (si las fases no coinciden, la predicción sería de otro mar) y con caché de un valor,
   que es todo lo que una consulta al futuro necesita.

#### Tres decisiones del diseñador (24-ago-2026) que cerraron huecos de la auditoría

1. **La salida es FINITA y tiene final.** Que el parte se agote ES «se acabó la marea». La
   duración la sortea la SEMILLA entre **10 y 25 minutos** (`DURACION_MIN/MAX`), distinta en cada
   salida e idéntica en las 6 máquinas. La cifra pedida pasó a ser un **tope real**: se reduce el
   número de actos hasta caber y el resto se recupera **estirando** el guion — estirar alarga los
   tramos, o sea que la pendiente de Hs solo puede bajar y la cota se respeta por construcción
   (comprimir sería lo prohibido, y el bucle nunca comprime). Antes «pedir 1500 s» devolvía hasta
   2194; y sin el estirón, el reintento solo dejaba salidas de 331 s — los dos extremos, medidos,
   con test. La señal `Ocean.clima_agotado` avisa del final (una vez); el cierre en puerto que la
   escuchará es F7. El número duplicado (HUD vs red) murió: la duración vive en el generador.
2. **El dial BORRA el guion, para todos.** «Cuando se mueve el dial, se borra para todos y se
   sobreescribe lo que yo pongo.» Adiós al estado SUSPENDIDO y a `reanudar_parte()` — era poder
   deshacer algo que nadie quiere deshacer, y su aviso recomendaba una salida que en red no
   existía. `Ocean` descarta el parte al primer toque manual y su señal `parte_cambiado` es lo
   que la capa de red escucha para difundir el borrado (idempotente: no hace falta saber el
   motivo). El HUD pierde la rama «SUSPENDIDO», que pasó a ser código muerto.
3. **El precursor de mar de fondo: 1,5 m.** Ver el recuadro de §3.3 — implementado con la
   energía capada y el período del origen.

#### Lo que una auditoría adversarial encontró después (24-ago-2026)

Seis barridos con lentes distintas (consumidores de furia/lluvia, red, matemática, los dos
carriles, cobertura de tests, veracidad de los docs) + un refutador por lente + un crítico de
completitud: **33 hallazgos brutos, 26 sobrevivieron la refutación**. Los de red se arreglaron en
el momento (ver abajo). Esto es lo que queda **abierto y conocido**:

- 🔴 **El shader del océano NO declara `rain01`, `gust01`, `wind_dir` ni `wind_drift`**, y
  `Ocean.apply_frame_to_material()` se los escribe igual, cada frame, al vacío. Verificado a mano
  y medido por un agente en un proyecto aislado: 27 uniforms declarados y ninguno de clima.
  Consecuencia: **la lluvia no toca la superficie del agua** (ni espuma, ni brillo especular, ni
  cat's paws, ni estrías) y **el destello del rayo no promociona bandas** — el `lightning01` global
  no lo lee nadie, así que el fogonazo es solo la `DirectionalLight3D`. Es anterior a esta sesión
  (el archivo lleva sin tocarse desde el 23-ago 23:57 y HEAD tampoco los tiene), así que lo que
  este documento da por hecho de la fase A **no está en el archivo**. No se ha restaurado a
  propósito: son decisiones visuales sobre las que el diseñador ya iteró mucho, y volver a meter
  efectos que quizá quitó a mano sería peor que el hueco.
- ~~**El guion se acaba y nadie lo renueva.**~~ **Cerrado por decisión de diseño** (ver arriba):
  la salida es finita, el final es contenido («se acabó la marea»), la duración la sortea la
  semilla entre 10 y 25 min y `Ocean.clima_agotado` lo anuncia. Lo único que sigue pendiente es
  quién lo escucha — el cierre en puerto, F7.
- **El horizonte inmutable no se hace cumplir en ningún camino de producción.** `comprometer()`
  solo lo comprueba si le pasan `ahora`, y el generador nunca lo pasa — correctamente, porque
  escribe el guion entero desde cero y ahí no hay futuro que proteger. El contrato es real pero
  **solo aplica a EDITAR un parte vivo, y hoy nada lo edita**. El único sitio que pasa `ahora` es
  el test.
- **Nada del juego escribe un parte**: los tres llamadores de `generar_parte()` son los botones de
  caladero, la tecla P y el manejador de red de esos botones. Es una herramienta de debug con
  cableado de producción detrás, no una feature encendida.
- **El «lightning jump» casi dobla la exposición total a destellos** (medido: 53-76 rayos por
  sesión con parte contra 23-41 sin él) y mete 6-11 de ellos en mar en calma, donde antes había
  cero. El techo por segundo (≤3 destellos/s, XAG 118) **se sigue cumpliendo por construcción** —
  eso no cambia—, pero la exposición acumulada sí, y `reduce_flashes` pasa a importar más.
- **Coste**: con parte, `_apply_sea_state()` deja de ser un evento y pasa a ser un latido de
  ~4 Hz (70-76 % de los segundos de partida tienen al menos un re-espectrado), y
  `seconds_to_next_strike()` pasa de hash puro a 12 evaluaciones de spline por frame (113 µs
  medidos) porque el HUD lo pinta cada frame. Ninguno es crítico hoy; los dos están anotados.
- ~~**El canal RUMBO no tiene test** y `reanudar_parte()` no tiene ningún llamador~~ **Cerrados**:
  el rumbo tiene test (arranca alineado con el viento ±40° y rola entre actos), y
  `reanudar_parte()` **ya no existe** — el dial borra, no suspende (decisión 2, arriba).

Lo que **sí** se arregló a raíz de la auditoría: el paquete de bienvenida usaba `parte()` en vez de
`tiene_parte()` y por tanto **resucitaba en el recién llegado un guion que en el host estaba
suspendido**; la suspensión no viajaba, así que el `TsunamiDirector` —que escribe `Ocean.fury` en
cada tick— dejaba al host en carril manual con los clientes siguiendo el spline, para siempre y sin
un error en consola (ahora `Ocean.parte_cambiado` es la señal que la capa de red escucha, y generar
un parte **para** el director igual que hace el lanzador de tsunamis); la lluvia había perdido su
`RAIN_RATE_LIMIT` en el carril comprometido, con lo que el corte de la RETIRADA pasaba de ~1,2 s a
un frame; `rumbo_frente_en()` era el único accesor que ignoraba la suspensión; y `fijar_parte()`
calculaba `_rain` sin `rain_scale`, o sea dos fórmulas para lo mismo.

Y un aviso sobre el método: de los 26 confirmados, **uno era falso igualmente** (un supuesto
duplicado al reescribir un keyframe con la misma `t`). Sobrevivió a la refutación adversarial y no
sobrevivió a ejecutar el código. La refutación sube mucho la precisión; no la vuelve 1.

Y una que salió a favor: **el techo del caladero se cumple sin comprobarlo en tiempo de ejecución**.
Como el generador escribe todas las pendientes a cero, cada tramo es un smoothstep, que es monótono
entre sus dos nudos — así que un spline no puede sobrepasar el techo entre keyframes. El test lo
verifica igual con `extremos_en` (analítico, no muestreado) sobre 40 semillas × 4 caladeros, porque
la propiedad depende de una decisión del generador que alguien podría cambiar sin darse cuenta.

**Qué NO hacer (decisiones cerradas por la investigación):**

| Tentación | Por qué no |
|---|---|
| `TIME` en cualquier shader de clima | reloj local: rompe determinismo y pausa (§0) |
| `turbulence` en partículas de lluvia | ruido 3D caro por docs; para ráfagas basta animar `gravity` |
| Sub-emitters At Collision sobre el mar | ningún collider GPU evalúa nuestra función; presupuesto global con trampas |
| HeightField/SDF collision en el barco | geometría móvil: re-render constante / bake imposible; los Box analíticos sí |
| Cambiar `amount` en runtime | resetea el sistema; `amount_ratio` es el dial |
| Transparencia real en gotas/cortina | overdraw transparente es EL coste de Forward+ (#97903); alpha scissor |
| Bloom/`adjustment_brightness` para el flash | rompe las bandas y hace el delta fotosensible impredecible; promoción de banda |
| Volumetric fog para el flash | ghosting documentado con luces breves + coste base del froxel |
| Espuma acumulada en textura (patrón FFT) | es estado: rompe pureza y consulta a futuro; max de Jacobiano en t, t−1, t−2 |
| Rotar/re-escalar una ola activa | pop de fase garantizado; solo amplitudes, o reciclaje por cero |
| Tweens/corrutinas en los directores | el late joiner no puede reproducir una rampa; todo `evaluate(t)` |
| Shallow-water 2D para cubierta | proyecto en sí mismo (Still Wakes the Deep); plano con slosh retardado |
| Gotas/distorsión en la lente | screen texture prohibida + generador de incomodidad conocido |
| `distance_fade` con min>max para "ocultar lo pegado a cámara" | en Godot invierte el fade ENTERO: solo renderiza lo cercano — medido con `capture_aabb` (las 4000 gotas existían y se veían 5) |
| Gotas opacas de borde duro | en vídeo real la lluvia es mezcla fraccional con el fondo (Garg-Nayar/MSR): leen como barras molestas — puntas difuminadas + alfa |

---

## Fuentes principales

**Lluvia/render**: Sébastien Lagarde, serie *Water drop* (esp. 2b — dynamic rain, la biblia de la
lluvia en juegos) · Tatarchuk/ATI, *Artist-Directable Real-Time Rain* (ToyShop, SIGGRAPH 2006) ·
fxguide *Game environments B: rain* (timings de Remember Me) · Cyanilux *Rain Effects Breakdown*
(anillos/flipbook) · 80.lv *How Rain Works in Video Games* · GDC: *AC4 Black Flag — Road to
Next-Gen Graphics* · unitycoder/unity-botw-screenspace-rain (ingeniería inversa BotW).
**Godot**: docs oficiales de partículas 3D/colisión/sub-emitters/AudioStreamWAV/Environment/sky
shaders + issues #93567 (AABB mata colisión), #84753 (billboard vs align), #97903 (overdraw
Forward+), artículo oficial GPUParticles 4.0.
**Rayos**: Xbox Accessibility Guideline 118 · Game Accessibility Guidelines (flicker) · Tuts+
*2D Lightning Effects* (midpoint displacement) · hexaquo (bolt SDF en Godot) · Fineberg et al.,
*Advances in Thunder Sound Synthesis* (arXiv 2204.08026) · NOAA JetStream (flash-to-bang) ·
kmonkeygames (flash = luz + cielo) · Thunderhead mod (rayo por semilla, trueno retardado).
**Audio**: Andy Farnell, *Designing Sound* — practicals 9 (crujido), 15 (lluvia), 17 (trueno),
18 (viento), patches Pd en aspress.co.uk/sd · Tsugi (LOD de lluvia) · Sutkus (viento en runtime)
· QMUL (tono eólico f = St·v/d).
**Tormenta/juegos**: Sea of Thieves wiki + *The Technical Art of Sea of Thieves* (SIGGRAPH 2018)
· World of Warships wiki (tormenta como información) · Valheim (clima determinista) · Raft/
Stormworks/Sailwind/Windbound · DST `weather.lua` (código real leído).
**Viento/mar**: Van der Hoven 1957 (espectro de rachas) · NOAA Marine Beaufort Scale · LibreTexts
/Natural Navigator (cat's paws) · Ghost of Tsushima (vorticles, Game Developer) · GDQuest (flag
shader) · Nathan Gordon, *Wind Waker Graphics Analysis*.
**Física de lluvia sobre mar**: *Rain Calms the Sea* (arXiv 1812.08200) · Nature 342 (1989) ·
J. Phys. Oceanography 22 (1992) · Laxague 2020 (GRL).
**Océano/espectro**: Tessendorf, *Simulating Ocean Water* · GPU Gems cap. 1 · Horvath 2015
(spreading direccional) · *Arc Blanc* (arXiv 2503.03326, JONSWAP completo) · Crest (banco por
octavas) · 2Retr0/GodotOceanWaves.
**Red**: Gaffer On Games (snapshot interpolation, deterministic lockstep) · vorixo (stateful
replication / late join) · netfox docs (NetworkTime) · bugs documentados: No Man's Sky, Conan
Exiles, Terraria, Minecraft wiki.
**Confort**: arXiv 2103.05200 (rest frame vs viñeta) · See-Level VR · IEEE 8797800.
