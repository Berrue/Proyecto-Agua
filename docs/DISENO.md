# Documento de diseño — "el mar antagonista"

> Sintetizado de una investigación de 10 agentes (5 de investigación con ~40 fuentes verificadas,
> 3 propuestas de diseño independientes, 2 críticos adversariales que arbitraron los conflictos).
> Los números de este documento son **hipótesis medibles**, no constantes: se declaran variables
> de balance desde el día 1.

## La tesis

**Un solo gesto — tensar el sedal contra un mar que se mueve — escala de la calma social al
heroísmo sin cambiar de input, porque la dificultad no vive en la UI sino en la cubierta.**
El dial de furia decide qué verbo está abierto (pescar o sobrevivir). La victoria canónica es
**atracar vivo con la carga**; el tsunami es el jefe, no el final garantizado.

Somos el único juego que puede prometer esto honestamente: nuestro océano es determinista y
consultable en el futuro, así que la telegrafía nunca miente y la dificultad jamás se ajusta a
escondidas.

### Las tres estéticas objetivo (el filtro MDA)

**Fellowship + Challenge + Sensation.** Toda mecánica nueva se valida con una pregunta:
*¿qué dinámica social produce entre 2-6 amigos con voz por proximidad?* Si no genera gritos,
negociación o culpa cómica observable, se corta. Ejemplo canónico: la bomba de achique manual
que requiere ritmo produce dinámica («¡a la bomba!»); una automática no produce nada.

### Decisiones del usuario (cerradas)

| Decisión | Elección |
|---|---|
| Artes del slice | **Solo caña** — todo el presupuesto de feel en un verbo perfecto |
| Recuento del slice | **2-6 desde el slice** (+ modo solo con ayudas → efectivamente 1-6) |
| Jugador solo | **Jugable con ayudas** (pesca libre, bomba automática, cabo de trinca) |
| LEVIATÁN | **1 encuentro guiado garantizado** al final de la primera campaña; raro (~20-25 %) en lo sistémico |

---

## 1 · El loop, en cuatro frecuencias

El juego es una jerarquía de loops anidados donde cada loop paga en la moneda del superior
(modelo "turducken", GDC).

### Segundo a segundo: la caña (el verbo del día 1)

Siete pasos, 20-40 s por captura en calma. **Sin una sola barra de UI**: la caña, el sedal y el
carrete son la interfaz, legibles por los compañeros (pueden gritarte «¡suelta!»).

1. **Cebar** (2 s).
2. **Lanzar**: mantener-soltar con arco físico visible.
3. **Espera** 8-25 s. La caña puede clavarse en un soporte de borda (libera las manos); la caña
   desatendida se dobla y suena — señal de estación.
4. **Picada**: ventana generosa de 1,5-2 s. Fallarla = el pez se va, cero castigo extra.
5. **Lucha** 5-20 s: el pez tira en una dirección que cambia cada 1-3 s; tiras en contra y
   recoges cuando afloja. Dos manos ocupadas: **no puedes agarrarte**.
6. **Izado**: el pez cae a cubierta como rigidbody (comedia física gratis).
7. **Estiba**: porteo a la bodega.

**La fórmula que une pesca y mar** — un sistema, dos sensaciones:

```
tensión = tirón(pez) + k · |aceleración_vertical(borda)|
```

La aceleración de la borda es *analítica* en nuestro Gerstner: pescar con furia 7 es
objetivamente más difícil con el mismo input, sin rubber-banding posible. Umbrales: T > 0,8 →
el carrete chirría (aviso ≥1 s); T ≥ 1,0 sostenida → latigazo cómico, pez perdido, caña intacta.
Por furia: 0-2 casi automática (pescas mirando al amigo); 3-4 lucha real; 5-6 peces ×2-3 de
valor; **≥7 solo pesca "heroica" y ahí viven las legendarias**; 9-10 pesca imposible — el verbo
cambia a sobrevivir sin ninguna pantalla que lo anuncie.

Referencias: Sea of Thieves (pesca diegética legible por terceros), DREDGE (postmortem:
*"fishing should not be frustrating"* — el minijuego optimiza, nunca decide el fallo).
**Rechazado**: minijuego con barra estilo Stardew (apilar un examen de UI sobre el examen físico
del mar duplica frustración y mata la charla).

### El segundo verbo: ACHICAR (el agujero nº 1 que señaló la crítica)

La bomba manual es lo que hace cada jugador sobrante en el minuto 12; si bombear aburre a los
90 segundos, la mitad del juego aburre. **Recibe el mismo presupuesto de feel que la caña.**

Diseño propuesto (a prototipar): bomba de palanca de dos posiciones. Bombear = ritmo de
mantener/soltar **leído del manómetro**, no mostrado en HUD: el caudal máximo vive en una banda
de cadencia; demasiado rápido cavita (caudal cae, la bomba escupe y traquetea — feedback
cómico), demasiado lento no vence la columna. **El cabeceo desplaza tu ritmo**: la furia modula
el achique igual que modula la caña, por la misma vía física. 1 persona = 50 % del caudal;
2 personas (una bombea, otra dirige la manguera a la celda correcta) = 100 %. Elegir *qué celda*
achicar primero es la decisión.

### Minuto a minuto: el ciclo de marea, con sus cinco decisiones

Llegar al caladero → calar/lanzar → esperar (los delays son los huecos donde se rota y se
habla) → izar → estibar → decidir. Las cinco decisiones nombradas:

1. **Qué caladero** (en puerto, con el parte del día).
2. **Dónde calar** (las aves y el sonar marcan bancos).
3. **¿Izar ya o dejar que llene?** — más pesca = más exposición al siguiente acto.
4. **¿Una tanda más?** — cumplida la cuota, cada tanda extra paga +15 % acumulativo (hasta
   +45 %) mientras la furia sube. La discusión por voz ES el juego.
5. **Ruta de vuelta**: directa con mar de costado (rápida, peligrosa) o larga con mar de popa.

### Sesión (25-35 min): la plantilla

Gancho ≤2 min (se zarpa con el mar visible desde el muelle) → travesía y calma (charla, primera
pesca) → tormenta (primera vía de agua, mini-clímax) → **calma engañosa** (¿puerto o una tanda
más?) → escalada y AVISO → IMPACTO → **RESACA protegida** (2-4 min, prohibido spawnear
amenazas: rescates, recuento, risas — los valles fabrican la anécdota) → vuelta, lonja,
bitácora, «¿otra?». La curva es fractal: cada acto repite gancho→escalada→pico→valle (Schell).

**Tres cierres válidos y legibles**: atracar con cuota = victoria; atracar sin cuota = parcial;
naufragio = derrota-anécdota (se pierde la captura, el barco mejorado se reflota en puerto —
hundirse es barato, fallar la *temporada* es lo caro). La bitácora registra la causa exacta
(«COLOSO, furia 7, celda de proa») y el replay del hundimiento se rebobina por semilla.

### Meta: la campaña

Temporada = 4 salidas; la cuota es **por salida** y la temporada es la *suma* (arbitraje del
crítico: la versión "por temporada" se cumplía en 2 lances y mataba el greed loop). Licencias de
caladero como progresión, Mareas como dificultad apilable post-victoria.

---

## 2 · Roles: el barco es la clase

**Decisión fundacional: estaciones físicas, cero clases, cero skills por jugador.** El rol es
la estación donde estás parado o el objeto que llevas en las manos; se ocupa y abandona al
instante. «Capitán» y «pescador» son nombres de *posiciones*, no de personas — y por eso rotan
solos, que es exactamente lo que pidió el usuario.

Evidencia unánime: los 4 éxitos friendslop (PEAK, Lethal, Content Warning, R.E.P.O.) tienen
cero clases; todos los juegos de tripulación con clases (Barotrauma, PULSAR, Void Crew)
necesitan *bots* para funcionar con pocos jugadores. La academia (Harris/Hancock, CHI PLAY 2016)
confirma que la asimetría de **información** basta para generar conexión social sin habilidades
asimétricas.

### Las seis estaciones

| Estación | Hace | Ve (asimetría) | No puede |
|---|---|---|---|
| **TIMÓN** | Proa a la ola (<20° reduce el agua embarcada — física real de las celdas), telégrafo del motor | La respuesta del barco: deriva, ángulo de encuentro | Pescar ni achicar; la rueda ES su agarre. Cabo de trinca: rumbo mantenido 12 s (6 s con Hs>6 m) |
| **CABINA/SONAR** | Verbaliza: «¡COLOSO por babor, 50 segundos, soltad la red!» + 3 interruptores remotos + cuadro eléctrico | **El futuro**: telegrafía según tier de sonar, bancos, radio meteo | No ve la cubierta a su espalda; cero autoridad mecánica |
| **APAREJOS/BORDA** | La caña (y las artes compradas) | El agua cercana: tensión, picada, bancos | Soltarse rápido con un pez grande enganchado — cortar el sedal ante un AVISO es la decisión que duele |
| **MÁQUINAS/ACHIQUE** | Bomba de 2 posiciones, tapones, cuadro eléctrico (el motor viejo alimenta solo 2 sistemas a la vez) | El interior: celdas, presión — **y un ojo de buey** | Corrección del crítico: la portilla pequeña da horizonte (anti-mareo) y deja VER la montaña de agua acercarse sin poder hacer nada más que bombear — terror y comedia; no da datos, da pánico |
| **ESTIBA/BODEGA** | Estibar rigidbodies en celdas, cerrar escotillas ante el AVISO, hielo | El peso: reparto de carga y escora | Escotilla abierta para pasar peces rápido = celda que embarca en tormenta — estanqueidad vs velocidad, negociada a gritos |
| **VIGÍA** (cofa) | Canta la retirada, las olas rebeldes, el hombre al agua | El horizonte, antes que nadie | Manos ocupadas en la jarcia; el puesto más expuesto |

Con el recuento 2-6 del slice decidido por el usuario, la cofa de vigía entra **de base** (era
la respuesta de la propuesta 2 al problema del 6º jugador); su test de existencia — quitarla y
ver si el viaje cojea — decidirá si sobrevive.

### Roles-objeto portátiles

El rol es lo que llevas: **BICHERO** (pez >25 kg, enganchar al hombre al agua), **LÁMPARA DE
TORMENTA** (única luz portátil de noche — ya tenemos ciclo día/noche), **RADIO PORTÁTIL**
(enlace cubierta↔máquinas), **CAJA DE HERRAMIENTAS** (sin ella no se tapona). Y la **LLAVE DEL
MOTOR** cuelga del cuello de alguien: si cae al agua con ella, misión de rescate emergente (el
patrón cámara de Content Warning). La llave se hunde; la lámpara flota.

### La rotación la fuerza el mar, no un menú

Sin fatiga, sin timers: **cada acto del director cambia qué estaciones son críticas**. CALMA:
aparejos y estiba (n−1 tareas: el hueco es para hablar). TORMENTA: la pesca CIERRA y mandan
timón+achique. AVISO: todos a asegurar (la ventana de 20-90 s con tareas para todas las manos).
RESACA: rescates y recuento. Las disrupciones invalidan el reparto vigente (la ola te arranca el
objeto, la celda anegada obliga a mover la bomba, el hombre al agua vacía un puesto).

**Regla n+1, reformulada por el crítico**: en pico hay n+1 tareas *visibles*, de las cuales solo
n−1 castigan de verdad si se ignoran (las otras cuestan rendimiento, no supervivencia).
Overcooked usa "más tareas que manos", no "más castigos que manos".

**Señalización diegética** (autoasignación sin UI): cada estación grita cuando falta — el timón
suelto gira y la proa cae atravesada, la caña se dobla y el carrete zumba, la bomba desatendida
traquetea, la carga suelta golpea el casco. El barco es el HUD. Esto hace del **audio una
mecánica, no ambientación** (dependencia crítica señalada por ambos críticos).

### Interdependencia por eficiencia, jamás por candado

«Hard no» oficial de Deep Rock Galactic a los candados de rol. Todo lo completa 1 persona lento
y feo; con 2 coordinados, rápido y con estilo: chigre elástico (1×/1,8×/2,4×/2,8× con 1-4
manos), rescate (solo: parar el barco + escala, ~45 s; en pareja: cabo + bichero, ~12 s), pez
grande (caña + bichero), bomba (50 %/100 %), el chaleco salvavidas **te lo abrocha otro** (PEAK).

### Escalado 1→6 (el océano JAMÁS escala)

El mar es idéntico para todos — es el pilar determinista y la coherencia diegética. Escalan:
cuota ×1,0/1,18/1,35/1,50/1,65 (2→6, sublineal: con 6 sobra margen para el cachondeo), vías de
agua simultáneas 1/2/2/3/3, crisis en pico = n+1 visibles, tareas en calma = n−1.

| Jugadores | Experiencia objetivo |
|---|---|
| **1 (solo)** | Pesca libre con ayudas: burra de achique automática, cabo de trinca. No es LA experiencia; es la prueba y el aprendizaje del mar. Sin cuota. |
| **2** | «Vamos justos pero podemos»: el déficit de manos es la comedia. Burra al 40 % del caudal, tsunami nunca exige >2 puestos activos. |
| **3** | El peor caso histórico del género (Overcooked): playtest dedicado. El tercero es el comodín que sigue la señalización diegética. |
| **4** | El recuento de referencia del balance. Especialización blanda emerge sola; cada tsunami la rompe y la reorganiza. |
| **5** | Las mejoras compradas crean el 5º puesto (2ª bomba, sonar como vigía). Nadie es «el Scavenger» (aviso de Void Crew). |
| **6** | El circo glorioso: coordinación y estorbo físico en cubierta estrecha, cadena de gritos completa proa→máquinas. Modo fiesta, no modo difícil. |

---

## 3 · Economía y progresión

### El pescado

Una moneda (dinero de lonja). El pescado tiene dos valores: **kg** (cuota — la línea de llenado
es física, visible en bodega) y **monedas** (por especie). Bandas indexadas a la furia: banda A
(furia 0-3) sardinas de 4-8 monedas; banda B (3-6) bacalao/fletán 30-150 (el fletán de 20 kg
exige 2 personas); banda C (6+, noche, o retirada) atún de 400-700; **legendarias** solo con
furia ≥7 **o durante la retirada pre-tsunami** (1 de cada 12-20 lances, 500-900 + nombre en la
bitácora). El pescado sin estibar: −25 % y puede barrerlo una ola — **el botín está en riesgo
hasta el puerto**.

*(La regla "legendarias también en la retirada" resuelve la contradicción que cazó el crítico:
la grúa no opera con furia ≥7, así que sin la retirada las legendarias de 120 kg eran
matemáticamente imposibles de subir a bordo.)*

### Cuota (arbitrada)

**Por salida**: base 60-120 kg con 2 jugadores, dimensionada para ocupar el 60-70 % del tiempo
de pesca de la salida. La temporada (4 salidas) suma. Crecimiento decreciente entre temporadas
con **techo duro** — nunca más del 60 % del extraíble, donde la tabla precomputada por semilla
es solo la *cota inicial*: el techo real se fija por telemetría de beta (percentil 40-50 de
capturas reales), porque el máximo teórico sin humanos sobreestima siempre (corrección del
crítico — es como Lethal Company reconstruyó su muro "matemáticamente imposible"). Modo pesca
libre sin cuota desde el día 1.

### Fracaso (arbitrado): el friendslop perdona

- **Naufragio** = barato: se pierde la captura, el barco se reflota en puerto.
- **Cuota de temporada fallada** = deuda acumulativa. El prestamista **precinta** una mejora
  (visible a bordo, recomprable con recargo) — jamás desinstala, y **jamás toca mejoras que
  crean estaciones** (castigar quitando puestos de rol es el anti-patrón Scavenger fabricado
  por el propio castigo).
- **No existe el fin de campaña.** El despido de Lethal Company es exactamente lo que su
  comunidad modea para eliminar. Como opción de lobby («modo deuda dura») para quien lo pida.

### Árbol de mejoras del barco (compartidas, visibles, ~22 ítems)

Cinco ramas, precios en curva ×1,7, **prohibido «+5 % de X»**: cada compra es una pieza visible
en el low-poly con efecto físico, y **toda mejora mayor añade una estación** — el árbol de
compras ES el sistema de escalado de roles (la tripulación compra literalmente su propio caos):

1. **CASCO** (gate, estilo Dredge): resistencia por celda → +2 celdas y mamparos.
2. **BOMBAS**: manual → 2ª bomba (estación nueva) → eléctrica conmutable (consume el cuadro).
3. **MOTOR**: velocidad → «trucado» *(unstable)*: +30 % pero se ahoga si máquinas se inunda.
4. **APAREJOS**: caña → red con chigre → nasas → palangre. Cada arte, una estación.
5. **LUCES + BODEGA/HIELO**: noche jugable y capacidad.

**El SONAR — la mejora estrella que ningún competidor puede copiar** (vende literalmente nuestra
telegrafía): T1 campana «algo viene» / T2 ETA y rumbo / T3 tier y altura. **Regla de justicia
(arbitrada)**: las señales naturales gratuitas — retirada, pájaros, radio, espuma — garantizan
SIEMPRE el aviso mínimo por tier; el sonar vende *precisión*, jamás el aviso en sí. La justicia
no se compra. Y solo informa si alguien lo mira: comprar sonar es comprar el rol de vigía.

### Progresión persistente: modelo PEAK, cero meta-poder

Entre campañas persisten solo: licencias de caladero (basta que UN jugador del lobby la tenga —
el veterano lleva a los novatos), Mareas apilables, cosméticos/badges, y la bitácora. Cero
stats del jugador: la progresión real es de habilidad (leer el mar) y de barco. PEAK vendió 10 M
sin meta-poder; el endgame de DRG exige años de live-ops que 4-6 USD no pagan.

### Sinks

Factura en puerto (diésel por distancia, cebo, hielo, reparación proporcional al daño que el
jacobiano ya mide) ≈ 15-25 % del ingreso. **Nunca medidores dentro de la run** — DREDGE cortó el
combustible por tedioso. Converters de emergencia intra-run: tirar pescado para desescorar,
chatarra como tablones, un pez graso como bengala — cada kg gastado en sobrevivir no puntúa.

---

## 4 · Dificultad

### La dificultad se elige navegando (active DDA de Jenova Chen)

Cuatro caladeros con licencia; **los dos primeros abiertos desde el minuto 0** (arbitraje):
BAHÍA (furia máx 3, runs cozy válidas) → BANCO DE ARENA (máx 5, MURO garantizado) → LA FOSA
(máx 7, COLOSO) → AGUAS NEGRAS (máx 9, LEVIATÁN ~8 % por acto elegible). La conversación
«¿nos atrevemos a La Fosa?» sustituye al selector de dificultad. La furia **jamás** se modula
por rendimiento ni por valor de carga: la furia prometida es la furia entregada.

### Dentro de la run: sierra, no rampa (Left 4 Dead)

La furia sube **por actos e hitos de cuota** — nunca por reloj crudo (el reloj de Risk of Rain 2
castiga la actividad central; allí lootear, aquí pescar). Cada acto arranca 1-2 puntos por
debajo del pico anterior. Tras cada pico: **30-45 s de Relax garantizados**, y el valle no
empieza mientras haya un jugador en el agua o una celda inundándose (Peak Fade). RESACA sagrada.
El estado se comunica con un **barómetro de latón** con la escala Douglas nombrada («Marejada» →
«Mar Gruesa» → «Montañosa»).

Capa adaptativa mínima (`FisherIntensity` por pescador, decisión por máximo del equipo): ajusta
solo **cuándo** caen micro-eventos no deterministas (goteras, rachas, objetos sueltos) — el
ritmo, jamás la amplitud. **Frontera dura**: olas y tsunamis van por guion determinista; el
vocabulario adaptativo es todo lo demás.

### Tsunamis: jefes por guion, exentos del pacing

Cada tier exige una **lectura nueva** del agua (anti-burnout de la skill chain): MURO = orientar
proa y soltar lo que llevas; COLOSO = la decisión sobre la red a medio izar (cortarla = perder
el arte; jugársela = vuelco); LEVIATÁN = supervivencia pura con todos atados. Aviso mínimo =
tiempo de «asegurar el barco» del equipo más lento ×1,5 — hipótesis: MURO ≥20-25 s, COLOSO
≥40-50 s, LEVIATÁN 60-90 s con señal multicanal escalonada (pájaros −90 s → radio −75 s →
**la retirada visible** −60 s → sirena −30 s).

**El momento gif: LA RETIRADA.** El mar se retira 200-400 m y expone el lecho: peces premium
saltando en los charcos 30-45 s. Se puede bajar a cogerlos **con las manos** mientras alguien
canta la cuenta atrás exacta («¡vuelve, 15 segundos!»). El clip canónico: un amigo corriendo por
el lecho con un mero en brazos mientras el COLOSO crece al fondo. Anti-softlock: el barco queda
varado automáticamente durante la RETIRADA — no puede irse sin ti.

**El único arc del juego** (decisión del usuario): un LEVIATÁN garantizado y dirigido al final
de la primera campaña — todo el mundo ve la feature estrella una vez; su rareza sistémica queda
intacta. La *primera* retirada del mar de la vida de un grupo se guioniza dentro de ese
encuentro (silencio, pájaros, el casco tocando arena).

### Variedad entre runs

Semilla diaria (todos los grupos del mundo pescan «el mismo mar» ese día — conversación de
comunidad gratis), parte meteorológico como mutador consultable (niebla = el sonar sube de
valor; noche — **ya construida**; lluvia; mar de fondo), banco del día (especie ×2), pool de ~10
eventos raros de los que cada run ve 2-3, y **Mareas 1-7** apilables post-victoria (telegrafía a
la mitad, solo achique manual, noche cerrada, cuota +50 %, sin auto-sellado, radio rota, furia
base +1). Siete peldaños, no veinte: Slay the Spire 2 bajó a 10 y nuestra referencia PEAK usa 10.

### Muerte

Caer al agua = náufrago con voz, cuerpo recuperable (izarlo = tarea de 2, comedia). Ahogado =
**fantasma-vigía con voz** — lee el futuro *al nivel del sonar instalado* (arbitraje: la versión
«telegrafía gratis» creaba el incentivo perverso de que morir mejoraba la información del
equipo). Revive automático al cambiar de acto o en puerto (máx 5-8 min), o «boya milagrosa».
La voz JAMÁS se corta.

---

## 5 · El vertical slice (el corte, en voz alta)

El alcance total descrito arriba es 3-5× un slice. **El slice prueba una sola tesis**: *el mismo
input escala de calma social a heroísmo porque el mar decide el verbo.*

**ENTRA**: 1 barco (un layout, con cofa básica por la decisión 2-6), 1 caladero tipo Banco de
Arena con MURO garantizado, solo caña (con la fórmula de tensión completa), peces rigidbody +
estiba en **2 celdas de bodega dedicadas** (el doble servicio bodega=celdas de inundación
completo, solo tras test de legibilidad con 6), bomba manual **con el input diseñado**,
tapones/escotillas, telegrafía solo por señales naturales, director por actos guionizado (sin
capa adaptativa), RESACA protegida, pesaje en puerto con cuota física de UNA salida, náufrago
con voz sin poderes, 1-6 jugadores (solo = pesca libre con ayudas).

**SE CORTA** (fase 2+): red/chigre, nasas, palangre, tienda y árbol entero, temporadas/licencias
/prestamista, Mareas, semilla diaria, eventos raros, cuadro eléctrico, sonar por tiers,
FisherIntensity, MercyDirector, fantasma con telegrafía.

### Orden de validación (innegociable)

1. **GATE DEL PROYECTO — anti-mareo**: prototipo de la caña sobre cabeceo real de furia 5-7,
   con opciones de confort de serie (FOV, horizonte de referencia, reducción de cabeceo de
   cámara). Nadie ha combinado threshold-fight diegético en primera persona con cabeceo real.
   Si falla y no se mitiga, se rediseña la cámara ANTES de escribir más juego.
2. **Playtest a 2 ANTES que a 4**: es el caso más común y el más frágil (verificar que 1 bomba
   al 50 % + burra ≥ 1 vía de agua, o hay softlock matemático). Verdad incómoda que dijo el
   crítico: a 2, la cadena de gritos colapsa porque timón y carta se fusionan — el juego a 2 es
   Overcooked marinero, no KTANE naval. Hay que jugarlo como caso primero, no degradado.
3. **Playtest dedicado a 3** (el peor caso histórico del género).

### Agujeros conocidos (deuda de diseño declarada)

- **Cabina en TORMENTA larga**: 5-6 min mirando una pantalla que no cambia. Necesita
  micro-decisiones (cuadro eléctrico, partes de radio que piden respuesta, rumbo económico vs
  seguro). Diseñar antes del playtest a 4.
- **Onboarding/FTUE**: cómo 4 novatos aprenden la skill chain (espuma → retirada → telegrafía →
  proa) sin morir frustrados. La Bahía como tutorial encubierto, a diseñar.
- **Drop-in/drop-out y save**: quién es dueño del save del barco, qué pasa con cuota y vías de
  agua cuando el recuento cambia en caliente. Diseño de producto pendiente.
- **Sistema de clips**: si el marketing es «el clip de TikTok», el botón de captura/replay por
  semilla es feature del MVP, no un extra.
- **Audio como sistema**: la telegrafía multicanal y la señalización de estaciones son 50 %
  audio. Sin presupuesto asignado aún.

### Mercado (actualizado por el crítico)

**How to Fish** (lanzado 20-ago-2026) no es un aviso: es un fenómeno de **60-100k+ CCU**, 4º en
ventas globales de Steam. No compite en nuestro nicho (pesca+memes+armas, mar plano), pero
valida el apetito y sube la urgencia: **plantar la bandera del "mar antagonista" (anuncio/demo)
es ahora una decisión de negocio, no de diseño.** SHORE (balsa coop con tsunamis) sigue en Q4
2026. Nuestro foso defensivo es técnico y ya está construido: océano determinista consultable en
el futuro = telegrafía que no miente, retirada emergente, y un sonar que vende literalmente esa
consulta.

---

## Fuentes principales (verificadas por el crítico adversarial)

MDA framework (Hunicke/LeBlanc/Zubek) · *The Chemistry of Game Design* y skill atoms (Cook) ·
*Flow in Games* (Chen, tesis USC) · *The AI Systems of Left 4 Dead* (Booth — sierra, Relax
30-45 s, Peak Fade, jefes exentos, citas por re-verificar verbatim) · Interest curves (Schell) ·
postmortem de DREDGE · charla GDC de Slay the Spire · wiki/datos de Lethal Company (fórmula de
cuota corregida: el *incremento* es cuadrático, la cuota escala cúbicamente) · «hard no» de
Ghost Ship Games a clases-candado · KTANE GDC 2016 · Harris & Hancock (CHI PLAY 2016) ·
Beznosyk (ICEC 2012) · PEAK (10 M copias; 10 niveles de Ascent, el último cambia reglas) ·
Sea of Thieves «tools not rules». Sin fuentes inventadas detectadas en ~35 verificaciones.
