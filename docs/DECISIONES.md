# Registro de decisiones

Qué se decidió, por qué, y qué sigue abierto. Una decisión nueva o revertida se
anota aquí **en el mismo commit** que la implementa. El diseño de juego completo
está en `DISENO.md`; esto es la capa técnica y de proceso.

> El plan maestro F0–F8 vive en [`PLAN.md`](PLAN.md) (v2 del 23-ago-2026: integra
> los 5 fixes de la review; su cabecera explica qué se alineó con la realidad).

## Cerradas

| Decisión | Por qué |
|---|---|
| **Océano Gerstner analítico** como única fuente de verdad; FFT descartada | Un espectro FFT es estacionario por construcción: jamás produce un frente solitario (el tsunami saldría "subiendo el viento" — no sale). Y una textura de GPU no se puede consultar en el futuro ni da el mismo valor en 6 máquinas. |
| **Tsunami autorado como onda N** (cresta sech² + depresión adelantada) | La retirada del mar EMERGE de la fórmula (no está scripteada) y la telegrafía sale gratis: siendo función pura de t, cualquier cliente evalúa el futuro exacto. |
| **Los tiers escalan en 3 dimensiones** (altura lineal, anchura √m, celeridad de onda solitaria) | Escalar solo la amplitud da un acantilado vertical, no un tsunami más grande. Además: tier más grande = viaja más rápido = el director alarga el aviso en proporción (justicia). |
| **Flotabilidad por celdas** (sondas de volumen) con las 4 reglas + tope de estabilidad del drag | Resuelve el jitter que arrastra medio ecosistema de Godot y regala la inundación por compartimentos (escora sola, sin HUD). El tope repartido entre sondas se descubrió con el tier 3 (~31 m/s de corriente). |
| **Escala Douglas interpolada en Hs**, nunca en velocidad de viento | Hs escala como U²: interpolar U deja el dial muerto de 0-5 y explosivo de 8-10. |
| **Red: host-autoritativo + interpolación, sin rollback** (plan; aún sin implementar) | Coop de 2-6 amigos, no competitivo. El océano determinista reduce la réplica a semilla + reloj + furia (~50 bytes). |
| **GDScript tipado v1** (warning `untyped_declaration` activo) | Velocidad de iteración con seguridad razonable; C++/C# solo si un profile lo exige. |
| **Solo caña en el slice; 2-6 jugadores** (+ solo con ayudas) | Todo el presupuesto de feel en un verbo perfecto. Decisión de usuario, cerrada en el doc de diseño. |
| **Audio 100% procedural** (`SfxLibrary` sintetiza todo al arrancar) | Sin artista de audio y con licencia limpia garantizada. Nada de AudioStreamGenerator en vivo (cracking); todo pre-generado. |
| **Cámara anti-mareo traslacional-only** (cero rotación añadida, FOV ±5°, viñeta) | Primera persona sobre un barco que YA rota. Interpretación deliberada de Eiserloh + guías Meta: que nadie la "corrija" de vuelta. |
| **UI de pesca en pantalla** (flecha, ¡RECOGE!, barra fina) | La doctrina "todo diegético" falló el playtest de legibilidad. Primero se aprende, luego se presume: cuando el juego esté enseñado, pasará a ayuda desactivable. |
| **Vendorizar, nunca depender** + licencias en el commit que introduce la dependencia | Bases del ecosistema de agua de Godot: proyectos de una persona, poca validación. Ver `THIRD_PARTY.md` (incluye lista negra). |
| **Día/noche como función pura de `Ocean.sim_time`** | Cielo sincronizado gratis en red y consultable en el futuro ("¿será de noche cuando llegue el tsunami?"). |
| **Godot 4.7.2** (migrado desde 4.6.1) | El binario vive en `C:\Godot\4.7.2\`; el `godot` del PATH sigue siendo 4.6.1 — no usarlo. |
| **Casco modular: Blender editable → GLB visual → escena física nativa** | Reexportar arte no puede mover sondas, colisiones ni sockets en silencio. La topología vive en `.blend`; Godot conserva `RigidBody3D`, ocho sondas directas, colisiones simples y anclajes de mejoras. Contrato y fuentes en `docs/BARCO_MODULAR.md`. |
| **Ventana de rotura del sedal por TIER de pez** (1,5 s banda A → 0,45 s legendaria; antes 0,5 s planos) | Playtest: «rompe demasiado rápido». Avisar sin dar tiempo físico de soltar el clic viola la regla 8. El tier ES la banda hecha número (sin eje de dificultad oculto); el que pelea la legendaria ya entrenó reflejos con la escalera. Ver `docs/PESCA.md`. |
| **Cañas por tiers como puerta BLANDA** (`RodTier` ×3 en `resources/rod_tiers/`; sedal ×, carrete ×, gracia +, alcance ×) | Ninguna caña «desbloquea» peces: la física decide y el feedback se normaliza contra el límite del sedal MONTADO (chirría tu rotura real, no una ideal). Piezas visibles (empuñadura por color), nada de «+5 %» ocultos — la rama APAREJOS de DISENO §3 empezada. |
| **El cebo compra atención, nunca peces que el mar no da** (`TipoCebo`: acorta la espera y sesga el sorteo; jamás sube la banda) | Sumar furia falsa al sorteo era la implementación fácil y habría hecho aparecer atunes en calma: la tesis del juego (*el pez caro vive donde el mar es peor*) no puede comprarse en la lonja, igual que el sonar vende precisión pero nunca el aviso. El sesgo entra multiplicando la «cercanía a tu furia» que el sorteo ya usa, así que solo reordena lo que ya estaba disponible. Dos tests lo custodian. Ver `docs/PESCA.md` §5. |
| **La ventana de picada depende de DÓNDE está la caña** (`BITE_WINDOW` 1,8 s en la mano; `BITE_WINDOW_SOPORTE` 3,5 s clavada) | Con la caña en la mano el gesto es un clic; clavada hay que reaccionar, soltar la carga, cruzar la cubierta, apuntar y retomarla — medido contra los sockets `Gear*` reales pide ~2,1 s, así que 1,8 s planos hacían que la caña clavada pescara sola *para que el pez se fuera siempre*. Lo sostiene la física del *rod holder* (el pez se clava a medias contra una caña amarrada). Test contra la geometría del barco en `fishing_tests`. |

## Agua embarcada (2026-08-24)

| Decisión | Por qué |
|---|---|
| **El agua NO añade masa: quita empuje por celda** (`BuoyancyProbe3D.flooding`, un solo escritor por máquina) | Es equivalente en física y regala la escora hacia el costado anegado, el calado que crece y la respuesta pastosa sin una línea de HUD. Y hace que el punto sin retorno se pueda CALCULAR (`AguaEmbarcadaModel.flooding_neutro`) en vez de afinarlo a ojo. Las ocho sondas quedan `floodable = false` para siempre: el mecanismo nativo del addon inunda «mientras la celda esté sumergida», y las del pesquero viven medio metro bajo el agua en reposo — sería una vía de agua desde el primer segundo. |
| **Reserva de flotabilidad ×6 el peso** (sondas `volume` 1,5→3,0 y `height` 1,4→2,8; fuera el override `max_submersion_depth`) | Manda el TECHO DE INUNDACIÓN, no el oleaje: con la reserva vieja (×3) el barco perdía la flotación con el nivel medio en 0,667, por DEBAJO del 0,689 al que la cubierta queda al ras — se hundía antes de que se viera entrar el agua, y no había forma honesta de avisar (regla 8). Duplicar volumen y altura a la vez conserva el cociente V/h, así que la línea de agua y el periodo de cabeceo no se mueven: sube solo el techo. Medido: el oleaje se comporta igual y el LEVIATÁN pasa de sepultar el barco el 86 % del paso de la ola al 13 %, sin pop-up (pico vertical 21,8 vs 21,9 m/s). |
| **La tormenta embarca agua por MAR GRUESA, no por olas sobre la borda** (`embarque_por_mar`, cuadrático desde furia 5) | Medido, y contradice lo que el plan daba por hecho: con este océano a las olas les falta **más de un metro** para rebasar la regala incluso a furia 9 (Hs 18 m), y no hay ni un pantocazo. No es un fallo del modelo — las olas del espectro son largas y un pesquero de 13 m las cabalga siguiendo la superficie. `Ocean.get_breaking()` tampoco sirve de disparador: devuelve ~1,0 en todas las furias. Pero un pesquero en temporal SÍ embarca agua, y no por encima de la regala: entra pulverizada por el viento y a crestazos contra el costado. Eso es lo que se modela, y entra **por barlovento**, de donde sale gratis la decisión de qué celda achicar primero. Las olas sobre la borda siguen ahí para lo que sí las rebasa: el tsunami. |
| **Umbrales 0,55 (alarma) y 0,85 sostenido 3 s (naufragio)**, calculados en frío | Corrigen los de `CLIMA.md` §6.4 (0,75 y 1,0), escritos antes de tener la geometría: 0,75 caía POR ENCIMA del punto sin retorno (0,689), o sea una alarma que suena cuando ya no puedes salvarte. El naufragio va por encima del techo físico (0,833) para que la señal confirme lo que la física ya decidió, nunca lo provoque. `agua_tests` lee la escena real y exige la cadena `alarma < punto sin retorno < techo < naufragio`. |
| **La voz se pierde con LO QUE SE OYE, no con una curva propia** (`WeatherAudio.ruido01()` → `VozModel`) | El enmascaramiento de voz es la mecánica social del juego (CLIMA §3.5): en calma habláis de popa a proa, en temporal solo al lado. Si el ruido que tapa la voz fuera una curva aparte de la que mezcla las camas, bastaría con que alguien afinara una para que la voz se perdiera sin que el jugador oyera nada raro — feedback que miente (regla 8). Por eso el ruido lo publica el mismo autoload que mezcla el clima, como suma equal-power de lo que ya está sonando, y la furia entra por el viento y no por un término inventado. El filtro va en el BUS y no en el hablante porque es TU oído el que está tapado, no su boca. Y `tests/voz_tests.tscn` ata el número al casco: en el pico, el radio útil tiene que ser menor que la eslora, o la mecánica no existe. |
| **El dial de dificultad se prueba JUGÁNDOLO, no comparando caudales** | El ingreso no es constante: según entra agua el barco se hunde, se le entierran celdas y entra más — la espiral. Comparar dos números sobre el papel no la ve. El test simula furia 8 con la bomba a pleno (aguanta), con medio caudal (una persona sola pierde terreno) y sin nadie (naufragio en ~30 s). Cuadrar `embarque_mar_max` contra `caudal_bomba` es lo que fija la dificultad, y por eso los dos viven en el MISMO `.tres`. |
| **La bomba es un ciclo de dos tiempos, no un grifo** (`carga_camara`: mantener chupa de la celda, soltar escupe al mar) | Un caudal continuo premiaba apretar y no soltar, que es la ausencia de mecánica. Con cámara, mantener deja de ser óptimo solo: llena, la bomba deja de mover agua. Tres consecuencias que el grifo no daba. (i) El agua de la cámara **sigue contando a bordo** (`AguaEmbarcada.nivel` = celdas + cámaras): si no, chupar y no escupir nunca sería bajar el nivel gratis y burlar el umbral de naufragio. (ii) Como el agua sale de la CELDA al chupar pero del BARCO al escupir, cada tiempo tiene su feedback — chupar corrige la escora, escupir baja el nivel. (iii) La capacidad se cancela en `caudal_sostenido` (media armónica de los dos tiempos), así que más cámara es comodidad y no caudal: son los dos ejes separados que los tiers necesitan. |
| **El 50 % del solitario se despeja hacia la aspiración** (`factor_aspiracion_solo` → ⅓, no 0,5) | Lo cazó el arnés al estrenar el ciclo: el cabezal suelto solo estropea el tiempo de CHUPAR —escupir dura lo mismo lo sostenga alguien o no—, así que meter el 0,5 directo dejaba el ciclo al 67 % y la bomba habría sido un tercio más generosa de lo que promete DISENO, en silencio. Se parte del rendimiento que pide el diseño y sale el factor del único tiempo al que se le puede cobrar. |

## Hallazgos de la review del plan (2026-08-23) — estado

La review independiente del plan maestro dejó 6 hallazgos. Estado real a día de hoy:

1. **Olas rebeldes por re-faseo** contradicen la regla anti-popping, y con 8-16 olas
   el foco perfecto da cresta ≈ √(N/8)·Hs — insuficiente para 2,2-3×Hs.
   **→ Patrón resuelto, feature pendiente:** los tsunamis ya se hacen exactamente como
   proponía el fix (componentes DEDICADOS al evento, `OceanEvents`, con rampa propia).
   Las olas rebeldes sistémicas se implementarán con ese mismo patrón, no re-faseando.
2. **Contradicción `linear_damp` vs amortiguar contra superficie móvil.**
   **→ RESUELTO** en `FloatingBody3D`: drag por sonda sobre velocidad relativa a la
   superficie, con clamp de estabilidad; `linear_damp` bajo y constante solo de base.
3. **Costura jugador↔barco↔red sin diseñar** (simular jugadores en espacio local del
   barco; océano del cliente en el reloj retrasado de interpolación — ~100 ms ≈ hasta
   medio metro de error vertical si no). **→ CERRADO en diseño y R0 en código**
   (2026-08-23): los tres contratos en `docs/RED.md`, la matemática pura en
   `NetMath` con test, y `Net` (ENet localhost) aplicándolos. Falta validarlo
   con dos máquinas y latencia real.
4. **F1 "sin red" no puede responder su propia pregunta de diversión** con 2-6:
   hace falta ENet mínimo + agarre tonto + deck-walking antes de juzgar.
   **→ EN CURSO:** R0 da la red mínima (F9 = host, F10 = unirse: mismo mar,
   barco replicado, jugadores viéndose en cubierta). Para el juguete coop
   completo faltan props y porteo en red (R1 de `docs/RED.md`).
5. **El test de paridad CPU/GPU no corre en headless** (sin RenderingDevice — verificado).
   **→ Mitigado, no resuelto:** paridad visual con `parity_markers.gd` + lado CPU en
   `f1_tests.gd`. Pendiente: golden vectors regenerados en máquina con GPU + test GPU
   real como tool de editor.
6. **Menores, todos abiertos:** elegir driver (Vulkan dev / D3D12 ship — uno);
   el riesgo Discord (voz por proximidad compite con el Discord que ya usan los grupos);
   no hay break force nativo en joints 3D de Godot (afectaba al chigre/red — el
   diseño de `docs/CHIGRE.md` lo esquiva: la rotura vive en un modelo puro
   estilo FightModel y el cable es presentación, cero joints; queda pendiente
   solo si algún sistema futuro exige cuerda física de verdad);
   la estimación GDScript 0,1-0,3 ms era optimista y el presupuesto de sondas es solo
   del host; validar las 6 estaciones contra el rango 2-6 en playtest;
   **calendario**: SHORE (balsa coop con tsunamis) sale Q4 2026 y How to Fish
   (ago-2026) validó el apetito con 60-100k CCU — plantar la bandera del "mar
   antagonista" es decisión de negocio pendiente.

**Actualización 2026-08-24 — los dos criterios de rendimiento de F2 ya están medidos.**
Hasta hoy no había ni una sola medición de coste en el repo: cero `ticks_usec` en veintiún
arneses, todos de corrección. Ahora hay dos piezas, y son dos porque el criterio son dos
cosas distintas: `tests/perf_tests.tscn` (headless, física pura, **sale en rojo** si se pasa
del presupuesto) y `tests/capture_perf.tscn` (necesita ventana y GPU, no es un test sino un
informe con p50/p95/p99 y peor frame). Medido en build **debug** —el único disponible: no hay
templates de export de 4.7.2 instalados— sobre un i5-12400F con una RX 6650 XT:

- **Flotabilidad: NO cumple, y por mucho.** Las 200 sondas del criterio (el barco con sus 8
  celdas + 96 barriles) cuestan **~4,7 ms de mediana** contra un presupuesto de 2 ms, y
  **~2,9 ms incluso en el mínimo medido** — el suelo importa porque el ruido de la máquina
  solo puede sumar, así que no hay lectura del dato en la que esto quepa. De esos 4,7 ms,
  **~4,0 ms son `Ocean.sample()` solo**: el coste está en el evaluador, no en
  `FloatingBody3D`. Confirma con números el hallazgo 6 («la estimación 0,1-0,3 ms era
  optimista»): se pasa por más de un orden de magnitud. El plan ya previó la salida
  (`PLAN.md` §Lenguaje: bajar a C#/GDExtension **solo el evaluador de altura**), pero
  **antes de decidir nada falta repetir la medida sobre un export**: la VM de GDScript en
  debug paga comprobaciones por instrucción que el juego exportado no paga, así que este
  número es un techo, no la cifra final.
- **Frame time: el cuello es la CPU, no el mar.** En tormenta furia 7-9 el frame va a
  ~9-10 ms de mediana con solo **~4 ms de GPU**. Y la cola (p99/p50 ≈ 1,7) queda explicada
  entera por el aliasing de la física contra el frame: los frames que se comen **un** paso
  de física salen a ~8,9 ms y los que se comen **dos** a ~14,2 ms — esos ~5,3 ms de
  diferencia son exactamente una pasada de flotabilidad. Jugando con vsync a 60 Hz y la
  física a 120 Hz, **todos** los frames se comen dos pasos, o sea el caso caro siempre.
- **Consecuencia para el clipmap (que es el siguiente trabajo de F2):** la línea base dice
  que la malla de hoy (512 m, 255 subdivisiones, 66 049 vértices, 131 072 triángulos) cuesta
  ~4 ms de GPU y **no manda en el frame**. Multiplicarla por ~8 hay que medirlo contra esta
  tabla, pero lo que hoy limita no es lo que el clipmap toca. Las dos herramientas se repiten
  después del clipmap, y **hay que repetirlas en la GTX 1060**: el criterio se enunció contra
  ella y la máquina de desarrollo no lo es.

### 2026-08-23 — Porteo: manos + cinturón chico, sin inventario de grilla

**Contexto:** faltaba el sistema de agarrar/soltar/estibar ("inventario en
HUD"). El farol acababa de aterrizar como caso único, el pez capturado se
quedaba tirado en cubierta para siempre (el paso "estiba" del loop del día 1
no existía), y había que decidir el modelo antes de que cada objeto inventara
el suyo.

**Decisión:** el inventario son **las manos (0/1/2) + un cinturón chico
futuro (1-2 huecos, solo objetos chicos declarados)**. Sin grilla, sin
bolsillos genéricos, sin hotbar. Sistema generalizado desde el farol:
`Portable3D` (verbos) + `Portador` (las manos del player) + `Bodega` (estiba
por presencia física) + prompt mínimo. Lanzar con carga entra desde el día 1.
Diseño y fases en `docs/PORTEO.md`.

**Por qué:** DISENO.md ya lo decía — el rol es el objeto que llevás, la ola
te lo puede arrancar, el barco es el HUD. Un hotbar tipo Lethal (descartado)
disolvía el déficit de manos que sostiene las estaciones; el modelo
"solo manos" puro (descartado por poco) castigaba objetos chicos tipo radio
que el diseño quiere encima del cuerpo. El pez→bodega como primer cliente
cierra el loop de pesca en vez de estrenar el sistema con props de juguete.

**Consecuencias:** `hands_used`/`input_captured`/`carry_slowdown` son EL
contrato del player (la lucha de la caña y el porteo a dos manos ya no son la
misma cosa); la caña respeta las manos (`_hands_free()`); la cuota será
física (kg presentes en la celda, señal `carga_cambiada`); la red de F4
recibe verbos con costura de autoridad ya hecha. Deuda: cinturón y
roles-objeto (fase B), porteo a dos personas y autoridad en red (fase C).

### 2026-08-23 — Red mínima R0: la costura cerrada, ENet detrás de una puerta

**Contexto:** los dos hallazgos más viejos de la review seguían abiertos — la
costura jugador↔barco↔red sin diseñar y un F1 que no podía responder su
pregunta de diversión en single-player. El porteo (fases A y B) dejó listo el
agarre que el gate necesita.

**Decisión:** cerrar la costura como TRES contratos escritos (`docs/RED.md`):
jugadores replicados en espacio local del barco; el cliente evalúa el océano
en el reloj retrasado de la interpolación (persecución con slew acotado,
jamás saltos); autoridad en cuatro niveles sin predicción, con el barco del
cliente congelado KINEMÁTICO. E implementar R0: autoload `Net` (ENet
localhost, F9/F10 o `--net-host`/`--net-join`), semilla+reloj+furia+lluvia
replicados, barco interpolado, jugadores con cuerpo visible y animación por
los mismos tres números del animator local. `NetMath` es pura y testeada;
`net_tests` incluye un loopback ENet real en un proceso.

**Por qué:** el plan entero es una apuesta sobre la pregunta de F1 («¿os
reísteis?») y esa pregunta es coop. El océano-función-pura hace la red barata
(~50 bytes de estado), así que el esqueleto costaba días, no semanas — y es
el mismo esqueleto de F2.

**Consecuencias:** el HUD de debug manda solo en el host (el goteo pisa al
cliente que toque el slider); los props y los peces DIVERGEN entre máquinas
hasta R1 (host-autoritativos + spawn vía host + porteo con transferencia de
autoridad = PORTEO fase C); los eventos del océano se replicarán como la
llamada `spawn_tsunami_tier` + sim_time (el RPC fiable de ~50 bytes del
plan); Steam y voz quedan para R2, detrás de la misma puerta `Net`.

### 2026-08-23 — R1: los props en las mismas manos, con agarre pesimista

**Contexto:** R0 dejaba el mundo replicado a medias — barco y jugadores sí,
props y peces no. Cada máquina simulaba sus propios barriles y peces, así que
dos amigos veían mundos distintos en cuanto algo se movía.

**Decisión (cinco, y su porqué):**

1. **Agarre PESIMISTA, no optimista.** El cliente pide y espera; el prompt
   dice «pidiendo…». La regla 8 dice literal «me avisó, nunca me robó», y un
   agarre optimista revocado por el host ES «me robó»: el objeto aparece en tu
   mano y desaparece 120 ms después, sin forma de telegrafiarlo antes. Con
   80-150 ms se lee como estirar el brazo. El host agarra al instante porque
   ES la autoridad — la misma asimetría que ya pagan los clientes por el barco.
   Si el playtest a seis lo rechaza, el repliegue NO es optimista pelado: es
   pre-validar en el cliente para que el 99 % de las peticiones se acepten y
   dejar el viaje solo para la carrera real.
2. **Identidad por lista literal** (`NetPorteo.CUERPOS_ESCENA`), no spawn
   table: los cinco props tienen nombre estable e idéntico en las dos escenas,
   y negociarlos sería mandar por el cable algo que las dos máquinas ya tienen
   escrito en disco. La lista es **append-only**: el índice ES el id. El día
   que el mundo deje de ser una escena autorada, esto necesita una spawn table
   de verdad.
3. **La bodega NO lleva red propia.** Cuenta por presencia física, que es una
   función pura de las posiciones, así que con los cuerpos replicados la cuota
   coincide sola — verificado con un test dedicado antes de escribir nada más,
   porque era una suposición sobre el motor y de ella colgaba el diseño
   entero. R1 no consume nada de su API. Pero `Bodega.kg` de un cliente no es
   verdad de juego: el día que algo decida con ese número (vender en puerto,
   condición de victoria), el host tiene que ser la única verdad.
4. **La latencia se simula en RECEPCIÓN** (`NetLag`, propio, ~120 líneas). Es
   lo que modela el jitter contra el buffer de interpolación, que es
   justamente lo que se quiere probar, y deja el camino de producción intacto
   (con demora 0 la primera línea devuelve false). Se descartó vendorizar
   netfox entero por su fila en THIRD_PARTY.md y su auditoría.
5. **Nada de maquinaria nativa de replicación**, y el motivo es el MECANISMO,
   no una medición: la identidad de un `MultiplayerSynchronizer` es su ruta
   absoluta y se renegocia en cada salida/entrada del árbol, mientras que
   `Portable3D.tomar()` REPARENTA el objeto al marker de la cámara de quien lo
   coge. Un prop congelado para siempre tras un agarre con latencia, o un pez
   que se borra del mundo de tus cinco amigos al cogerlo. Hay un test que
   vigila que no aparezca ninguna.

**Consecuencias:** `Net` pasa de 413 a ~1.400 líneas y es el único sitio de
`game/` fuera de `game/net/` que otros archivos consultan (`portador.gd`,
`fishing_rod.gd`, `tsunami_director.gd` y el HUD de debug leen su rol). El
estado estable cuesta 0 bytes/s gracias al bit DORMIDO. El despawn de peces a
60 m es **diseño de pesca disfrazado de red**: el número está en una constante
con su comentario y hay que cerrarlo en playtest. Y quedan sin replicar: la
máquina de pesca de los compañeros (ves su cuerpo y sus manos, no su caña) y
el porteo a dos personas.

### 2026-08-24 — El vuelco: el mar te devuelve mientras te quede reserva

**Contexto:** medido, el barco volcaba con el LEVIATÁN y se quedaba flotando **boca
abajo indefinidamente** (172-179° el resto de la simulación, en 1 de cada 3 intentos).
No lo causaba el tsunami ni el rebalanceo de flotabilidad: soltando el barco a **80° de
escora en mar plana** también terminaba a 180° y se quedaba ahí. La causa es geométrica
y estaba desde F1 — las ocho celdas viven todas en el mismo plano horizontal (y = −0,7),
así que el empuje que reparten es simétrico respecto a ese plano y el casco flota igual
de bien del derecho que del revés. Medida la curva de par del casco desnudo (giro
bloqueado, bodega seca, en el equilibrio de calado, y ya con los brazos arreglados —ver
la decisión siguiente—): adriza hasta ~78° y a partir de ahí empuja **hacia** el vuelco,
con su peor momento en −48 kN·m a 150°. Bajar el `center_of_mass` tampoco arregla eso:
0,45 m de lastre no compiten con los ~3,6 m de brazo metacéntrico que le da la manga, y
el barco sigue siendo igual de estable invertido.

**Decisión:** el pesquero es **autoadrizante mientras conserve reserva**.
`FloatingBody3D` gana un `brazo_adrizante` en metros —el GZ del arquitecto naval— que
aplica un par de `peso × brazo × curva(escora)`: **cero por debajo de 45°**, pleno
pasados 100°, multiplicado por la reserva intacta (1 − inundación) y por lo mojado que
esté el cuerpo, y con un freno proporcional que lo convierte en una maniobra a ~35°/s en
vez de una patada. Por defecto vale 0: un bidón, un farol o una caja no tienen un
«arriba» que recuperar. El barco lo lleva a **3,5 m**, y de ahí salen los dos números
que importan: vuelve de cualquier escora en 1-7 s con la bodega seca, y **deja de volver
a partir del ~65 % de inundación** — o sea, después de que la alarma de sentina (0,55)
lleve rato sonando, y antes del umbral de naufragio (0,85). El estado se publica como
`volcado`/`adrizado` para el REVOLCADO del jugador de F4, el aviso y el audio.

**Por qué:** las tres salidas posibles se midieron antes de elegir.

- **Par adrizante emergente, dándole a las sondas un perfil que genere recuperación.**
  Imposible sin romper otra cosa: la estabilidad de un cuerpo flotante la manda el ancho
  del plano de flotación (BM ≈ 3,6 m aquí), así que para que el barco fuera inestable
  del revés habría que bajarle el centro de masas **más de 3,6 m** — un barco con quilla
  de plomo que rueda como un corcho. La alternativa honesta era colgar celdas estancas
  sobre la cubierta (que es lo que hace autoadrizante a un salvavidas de verdad), y eso
  choca de frente con el agua embarcada: una celda que la bodega no puede inundar es
  empuje que no se pierde nunca, y un barco anegado hasta arriba dejaría de hundirse.
  Además rompe el contrato de las ocho celdas (`probe_count() == 8`, el área de
  flotación, el mapeo de la bomba, los ocho bytes de la réplica).
- **Aceptar el vuelco como fallo terminal con reflote explícito.** Es lo que el juego ya
  hace con el naufragio, pero aplicado al vuelco convierte cada tsunami en una moneda al
  aire que termina la salida: mata la RESACA, que es el valle protegido donde el diseño
  pone los rescates y las risas (DISENO §1).
- **Adrizamiento parametrizado (lo elegido).** Es un par PURO: no suma ni un newton, así
  que no puede mover la línea de flotación, el francobordo ni el pico de velocidad con
  que el barco sale del muro — los números que `agua_tests` protege siguen intactos,
  verificado. Y no es magia con otro nombre: representa la cabina estanca, que es
  exactamente la pieza que el modelo de celdas no tiene, con la curva que tendría de
  verdad (seca no aporta nada; muerde cuando se hunde). Que vaya multiplicado por la
  reserva es lo que impide que sea un truco: **el agua sigue siendo lo que mata**.

**Consecuencias:** el vuelco pasa de estado sin salida a **evento con precio**: vuelves,
pero con el agua que embarcaste. A furia 7, un vuelco cuesta ~0,2 de inundación, que es
un tercio del camino a la alarma. Quedan atadas dos cosas más:

- Hubo que arreglar la **puerta por la que entra el agua cuando el barco no está en
  pie**, porque `AguaEmbarcada` estaba aplicando fuera de su dominio dos fuentes escritas
  para un barco derecho, y entre las dos llenaban el barco volcado más rápido de lo que
  tarda en volver (0 → 0,76 en veinte segundos, más rápido que ninguna tormenta): las
  olas sobre la borda ya **no cuentan pasado el horizontal** (no hay cubierta donde
  embarcar) y el entierro entra proporcional a lo que la cubierta mire hacia arriba, con
  un resto de filtración del 10 % que no es cero a propósito — un barco volcado y
  anegado tiene que poder hundirse, o el estado sin salida vuelve a aparecer a 90°. Por
  debajo de 90° **no cambia ni uno** de los números que el balance afina.
- **Hallazgo que NO es del vuelco, anotado aquí porque salió midiéndolo:** con el
  balance de agua embarcada de hoy, **un LEVIATÁN llena el barco él solo** — medido al
  pasar el muro, 0,90 sin brazo adrizante y 1,00 con él (el barco que se mantiene
  derecho conserva las ocho celdas enterradas más tiempo; el que vuelca pronto se ahorra
  agua porque el aire queda atrapado). O sea que hoy un tsunami de tier 3 es naufragio
  seguro, y el barco boca abajo que se ve después es su consecuencia, no su causa.
  `ritmo_entierro` (0,15/s por celda) es de quien afinó el agua embarcada y aquí no se ha
  tocado; el arnés del vuelco corre el LEVIATÁN con el agua apagada y lo dice en su
  comentario.

- El límite de inundación del adrizamiento es un eslabón nuevo en la cadena de umbrales
  que `agua_tests` protege, y `volcado_tests` exige el orden completo:
  **alarma < deja de adrizarse < naufragio**. Si alguien mueve el brazo, la masa o el
  balance y el barco pasa a perder el adrizamiento antes de que suene la alarma, el
  arnés lo dice (regla 8: el fallo se telegrafía antes de castigar).

### 2026-08-24 — Los brazos de flotabilidad se miden desde el centro de masas (regla 5)

**Contexto:** salió midiendo el volcado. `FloatingBody3D` acumulaba el par de las sondas
como `(posición_sonda − origen_del_nodo) × fuerza`, pero Godot aplica `constant_force`
**en** el centro de masas y `constant_torque` **respecto a** él. Medido: el par salía
**idéntico** (+33.097 N·m a 20° de escora) con el `center_of_mass` del barco en −0,45, en
0 y en +0,45. O sea que el lastre del pesquero —puesto a propósito para que sea estable—
no entraba en la cuenta, y llevaba así desde F1 sin hacer ruido.

**Decisión:** medir los brazos desde el centro de masas real, leído de
`PhysicsServer3D.body_get_direct_state(rid).center_of_mass` (que ya viene rotado con el
cuerpo). Se usa el estado del servidor y no la propiedad `center_of_mass` porque esa solo
vale en modo CUSTOM, y hay cuerpos del juego cuya colisión no está centrada en su origen.
Queda anotado como **quinta regla** de `FloatingBody3D`.

**Por qué:** el término que sobraba no es ruido y además tiene el signo malo. Vale
`(centro − origen) × F` = 0,45 × peso × sin(escora) ≈ 6 kN·m a 20°, y **tumba**: bajar el
lastre restaba estabilidad en vez de darla, justo al revés de lo que espera quien lo baja.
Con el arreglo, el mismo barco pasa de +33.097 a **+39.157 N·m** de par adrizante a 20°, y
subir el lastre a +0,45 ahora sí penaliza (+27.080) — los tres números cuadran con
`0,45·peso·sin20°` al 0,05 %. El mismo offset arregla de paso el arrastre, que compone la
velocidad del punto alrededor del centro de masas y no del origen.

**Consecuencias:** el casco entero es más estable — el ángulo de estabilidad nula pasa de
~65° a **~78°** y el peor momento de vuelco de −57 a **−48 kN·m** —, así que el brazo
adrizante mínimo baja de 1,45 a 1,22 m. Se deja en 3,5 m: el límite de inundación sube a
0,65 y sigue cayendo entre la alarma (0,55) y el naufragio (0,85). Toca a **todos** los
cuerpos flotantes, no solo al barco. La excepción que NO cambia es el impulso del slam:
`apply_impulse()` recibe la posición respecto al origen y resta el centro de masas por
dentro, así que pasarle el brazo ya corregido sería descontarlo dos veces — está
comentado en el sitio para que nadie lo «arregle».

Y una consecuencia que se paga en el agua embarcada: un barco más estable escora menos,
entierra menos la cubierta y su espiral de inundación es más floja — a furia 8 el ingreso
baja de 0,0189 a 0,0152/s. Eso dejó en rojo la comprobación «sin nadie en la bomba la
tormenta se lo lleva», que medía a los 30 s. **No se tocó el dial**: es física correcta,
no un balance más flojo, y además esa comprobación era una muestra única pegada al umbral
y decidida por la fase del oleaje (el mismo escenario da 0,67 corrido solo y 0,46 corrido
detrás de los otros dos). Se alargó su ventana a 40 s, donde el nivel ya está en 1,00 y
la afirmación aguanta la fase. `ritmo_entierro` y `embarque_mar_max` siguen intactos, y
las otras dos comprobaciones del dial (dos bombeando empatan, uno solo pierde terreno)
pasan sin tocarlas.

### 2026-08-24 — La lluvia impone un piso a la furia (y el clima se llama «parte meteorológico»)

**Contexto:** la fase D del clima tenía anotado un `FuryTrack` —convertir la furia en spline
comprometido por adelantado— pero quedaba abierto qué pasaba con la lluvia, que en fase A se hizo
**independiente de la furia** a propósito (furia 9 con cielo seco es un estado válido). Faltaba
decidir si la lluvia tenía su propio guion o se quedaba como perilla suelta.

**Decisión:** dos cosas atadas.

1. **El invariante**, en palabras del diseñador: *si sube la furia no tiene por qué llover; si
   sube la lluvia sí tiene que subir la furia*. La lluvia impone un **piso** a la furia
   (`furia ≥ 6·lluvia`, o sea llovizna ⇒ furia 2, diluvio ⇒ furia 6), nunca al revés.
2. **El renombre**: `FuryTrack` pasa a ser **el parte meteorológico**, con canales (furia,
   lluvia, rumbo del frente, niebla). El término ya existía en `DISENO.md` («parte meteorológico
   como mutador consultable»); tener dos palabras para lo mismo era la vía rápida a que
   divergieran dos sistemas gemelos que comparten spline, horizonte, semilla y red.

**Por qué:** es la causalidad real del mar. El mar VIAJA y la lluvia no —una tormenta a 300 km te
manda su mar de fondo pero no su agua, de ahí que furia 8 seca sea legítima— pero la celda
convectiva que descarga agua descarga viento, así que el diluvio sobre mar planchado no existe. Lo
que compra es **legibilidad**: el jugador infiere como un pescador («empieza a llover ⇒ el mar
viene detrás»), y el clima deja de ser decorado para ser información accionable.

La regla vive en **quien redacta el parte, no en `Ocean`**: los canales siguen independientes y el
generador escribe primero la furia (sierra por actos + techo del caladero) y después encaja la
lluvia bajo las jorobas que le dan piso. El invariante queda cumplido *por construcción*, como el
techo fotosensible de los rayos, y se testea como propiedad del generador. Eso preserva el carril
manual: mar plano con diluvio sigue siendo imposible en el guion y **válido en el toybox**, que es
como el harness de capturas aísla visuales.

Descartado: acoplar la lluvia a la furia con una fórmula (mataría la independencia que el
diseñador pidió en fase A) y sortear el clima con `randf()` en vivo (rompe la semilla diaria de
DISENO — «todos los grupos del mundo pescan el mismo mar ese día»). Los dados existen, pero
derivados: `hash(semilla_diaria, caladero, acto)`, como ya hacen los rayos.

**Consecuencias:** el caladero pasa a prometer también el cielo (BAHÍA, techo 3, no puede pasar de
llovizna; el diluvio solo existe en LA FOSA y AGUAS NEGRAS), lo que extiende «la furia prometida
es la furia entregada» sin código extra. El diluvio cae en furia ≥ 6, justo donde el cruce a
«tormenta encima» de los rayos ya está activo, así que trae rayos sin tocar esa fórmula. Y da
vuelta lo que parecía el peor coste del refactor: que el director pierda la reacción instantánea
no es un impuesto sino **la** feature — un hito de cuota compromete la furia a `ahora + horizonte`,
y esos 90-120 s son el mar respondiendo (el mar de fondo llega antes que el viento, `CLIMA.md`
§3.3). Queda **abierto** si el rayo pasa a colgar del canal de lluvia en vez de la furia
(recomendado en el doc: hoy furia 8 seca tiene tormenta eléctrica, y en la realidad el rayo es
hijo de la nube, no del oleaje). Diseño completo en [`CLIMA.md`](CLIMA.md) §8 ítem 14.

**Implementado el mismo día** en `addons/ocean/clima/` (`ParteMeteorologico` + `GeneradorParte`),
con `tests/parte_tests.tscn` (97 comprobaciones). Tres cosas que el diseño no había previsto y que
el código obligó a decidir, todas anotadas en CLIMA.md §14 «Lo que se aprendió construyéndolo»:
la cota de pendiente necesita **dos** factores (el smoothstep pica 1,5× su media Y `dHs/dfuria`
varía dentro del tramo); en red, la perilla de dios tiene que apagar el guion para **toda** la
tripulación, porque suspenderlo solo en el host deja al host goteando furia que los clientes
ignoran; y el parte viaja en el paquete de bienvenida como **curva**, no como receta, porque
`generar_parte()` la escribe desde la furia y el reloj de quien la pide.

### 2026-08-24 — El clima es finito, el dial borra, y el mar por fin se adelanta

**Contexto:** el parte meteorológico quedó implementado y auditado el mismo día, con tres huecos
que eran decisiones de diseño y no bugs: qué pasa cuando el guion se acaba, qué hace el dial de
furia con un guion en vigor, y cuánto puede adelantarse la mar de fondo a la tormenta.

**Decisión (las tres son del diseñador, textuales):**

1. **«El clima es finito con final, aleatorio entre 10 minutos y 25 minutos.»** La duración la
   sortea la semilla (`DURACION_MIN/MAX` en `GeneradorParte`), así que varía por salida y coincide
   entre máquinas. Que el parte se agote ES «se acabó la marea»: `Ocean.clima_agotado` (se emite
   una vez) es el gancho que el cierre en puerto de F7 escuchará. La cifra es un tope real: menos
   actos hasta caber y **estirón** hasta el objetivo — estirar solo baja la pendiente de Hs, así
   que la cota de la investigación se respeta por construcción.
2. **«Cuando se mueve el dial, se borra para todos y se sobreescribe lo que yo pongo.»** Muere el
   estado SUSPENDIDO y muere `reanudar_parte()`: era poder deshacer algo que nadie quiere
   deshacer, y su aviso recomendaba una salida que en red no existía (la capa de red convertía la
   suspensión en borrado — «el feedback jamás miente» rota dentro del clima). Ahora `Ocean`
   descarta el guion al primer toque manual, lo dice con un aviso honesto, y `parte_cambiado` es
   la señal que la red escucha para difundir el borrado.
3. **El precursor de mar de fondo mide 1,5 m** (`PRECURSOR_HS_MAX`), no un porcentaje: portar el
   0,75 de los rayos daba furia 2 con Hs 8,67 m — la tormenta entera llegando antes. Con el tope
   absoluto, a furia 2 son ~2 m de cabeceo largo con el rizado intacto, y en mar grande el
   resultado es idéntico al de hoy (se auto-limita).

**Por qué (el hallazgo técnico del día):** el swell necesita **dos números, no uno**. La energía
va capada (1,5 m) pero el período tiene que ser el de la TORMENTA de origen (`hs_origen`,
Tp ~ 4·√Hs): normalizado a su Hs capado, el espectro del precursor pica en olas de ~50 m, la
máscara de bandas largas (≥150-250 m) lo filtra entero y el anuncio es exactamente **cero** —
medido por el test antes de que ninguna captura lo delatara. Energía moderada con período de
temporal lejano es, literalmente, la definición de mar de fondo.

**Consecuencias:** el juego telegrafía en el orden real por primera vez — rayos en el horizonte
(900 s), mar de fondo (300 s), pared de nubes (210 s), viento — y las tres ventanas están
declaradas una al lado de la otra en `ocean.gd`. El carril manual queda bit a bit intacto (test).
`weather_tests` 64, `parte_tests` 97, todo verde. Pendiente heredado: quién escucha
`clima_agotado` (F7) y las capturas GPU del precursor para validar el look.

## El menú principal (2026-08-24)

### 2026-08-24 — El juego arranca por una portada, y la portada es el mar
**Contexto:** no había menú: `run/main_scene` era el juguete de F1 y el multijugador se
levantaba con F9/F10. Hacía falta una puerta con los tres modos (solo, hostear, conectarse)
y un sitio donde ver los controles y elegir micrófono.

**Decisión:** `game/ui/menu/menu_principal.tscn` pasa a ser el `run/main_scene`, con el mar
del juego de fondo — el mismo `OceanSurface3D`, el mismo cielo y el mismo `DayNightCycle`,
no un vídeo ni una imagen. La navegación, la ayuda de controles y los ajustes guardados
viven en tres clases PURAS (`MenuNavegacion`, `ControlesBasicos`, `MenuAjustes`), como
`FightModel` o `NetPorteo`. Ver `docs/MENU.md`.

**Por qué:** un fondo renderizado sale casi gratis (ya estaba escrito) y encima ata el menú
al juego: si alguien rompe el agua, la portada se rompe con ella y se ve al arrancar. Y la
ayuda de teclas se LEE del InputMap en vez de escribirse a mano porque una lista escrita a
mano envejece en silencio (regla 8) y porque en un teclado AZERTY hay que enseñar `Z` y no
`W` — eso lo sabe el sistema operativo, no nosotros.

**Tres cosas que no son obvias y que el arnés fija:**
1. **La hora se congela** (`DayNightCycle.hora_congelada`, nuevo). Una portada no es una
   partida: si la hora corriera, quien deja el menú abierto veinte minutos vuelve a un mar
   de noche que nadie diseñó. Y al abrir la partida se pone `Ocean.sim_time` a cero, que es
   la otra mitad del mismo problema: sin eso se empieza a jugar al atardecer por haber
   tardado en decidirse.
2. **El menú deja el mar como lo encontró.** Le baja la furia a 1,6 para la foto —medido con
   `capture_menu`: a la furia de arranque (3) la nubosidad cierra el cielo y la pantalla
   entera se va al gris— y la devuelve al lanzar el mundo. Sin devolverla, todas las
   partidas empezarían con la marejadilla de los botones.
3. **El orden de las operaciones en red va al revés en cada modo.** Hostear carga el mundo y
   DESPUÉS llama a `Net.hostear()`, porque el host censa `get_tree().current_scene` y
   hostear desde el menú censaría una pantalla de botones. Conectarse hace lo contrario:
   `Net.unirse()` desde el menú y el mundo se carga en `connected_to_server`, para tener
   dónde decir «no hay nadie escuchando» — cargar antes deja al jugador en un mar vacío
   mientras la conexión falla en segundo plano. El puerto se sondea antes de hostear por lo
   mismo (regla 8: avisar antes de castigar).

**Consecuencias:** `run/main_scene` cambia, así que el ciclo de trabajo pasa a ser abrir el
juguete a mano (`--path . game/world/toybox.tscn`), que es lo que ya se hacía. Queda
pendiente el camino de vuelta (pausa y «volver al menú»), el menú es MUDO a propósito
—regla 10: el audio nuevo se genera con ElevenLabs, y no se va a colar un clic procedural
por prisa— y «Conectarse» pedirá un amigo en vez de una IP cuando exista el lobby de Steam
(R2). `tests/menu_tests.tscn` (74 comprobaciones) y `tests/capture_menu.tscn`.

### 2026-08-24 — El HUD de debug vive detrás de la Ñ

**Contexto:** el HUD de debug estaba SIEMPRE encendido en el toybox y en la escena de
tsunami: un panel que se come un tercio de la pantalla y, sobre todo, ocho atajos sueltos
por encima del juego. `B` reflotaba el barco, `P` escribía un temporal entero, `1/2/3`
tiraban un tsunami y `0` lo cancelaba — sin que nadie hubiera pedido nada de debug.

**Decisión:** el menú nace CERRADO y se abre y se cierra con **Ñ**. Cerrado no responde
ninguno de sus atajos, y además se apaga su `_process` (el readout se rehace entero cada
frame para nadie).

**Por qué:** la Ñ no la usa nada del juego y no está en el InputMap — el menú de opciones
lee de ahí los controles que enseña, y la puerta del debug no es un control del juego.
Gatear los atajos con la visibilidad, y no solo esconder el panel, es lo que hace que
cerrar signifique algo: si `B` siguiera reflotando con el panel apagado, cerrarlo sería
apagar la luz. Se reconoce por lo que la tecla ESCRIBE (`unicode` 241/209), por su etiqueta
localizada y por su POSICIÓN física (la del `;` en un QWERTY US), porque Godot no tiene
`KEY_Ñ` y quien no tenga Ñ en su teclado se quedaría sin menú sin un solo error que mirar.

**Consecuencias:** la perilla de furia sigue siendo sagrada (CLAUDE.md), solo hay que
llamar antes. El ratón NO se libera al abrir: sigue haciendo falta `ESC` para clicar los
deslizadores, igual que antes. `tests/hud_launcher_tests.tscn` protege las tres vías de la
tecla, que nace cerrado y que cerrado no lanza tsunamis.

### 2026-08-24 — `Esc` no pausa, y el ping lo mide el patrón
**Contexto:** el menú principal dejaba la partida como un viaje de ida (no había
forma de volver) y no había manera de ver quién estaba conectado.

**Decisión:** un autoload `Partida` con las dos pantallas de sesión — la tarjeta
de `Esc` (Continuar / Volver al menú / Salir) y la lista de `TAB` con los pings.

**Por qué así, y no de la forma normal:**
- **`Esc` NO pausa el árbol.** En cooperativo es imposible (el mar de los demás
  sigue) y en solitario se descarta a propósito, por dos motivos: que el juego se
  comporte igual jugando solo que acompañado, y porque un `get_tree().paused`
  dejaría muerto el HUD de debug del océano justo cuando el ratón está suelto —y
  ese HUD es la herramienta de validación del juego (CLAUDE.md). De ahí también
  el tamaño: la tarjeta es pequeña y centrada para dejar libre la columna
  izquierda, que es donde vive ese HUD. La tarjeta lo DICE en vez de fingir: «el
  mar no se detiene».
- **`Esc` sigue soltando el ratón** y reutiliza la acción `toggle_mouse` que ya
  existía, en vez de inventar una acción nueva sobre la misma tecla: dos acciones
  en la misma tecla es un conflicto esperando a que alguien lo redescubra.
- **El retardo lo mide el host y lo reparte a 1 Hz.** No es una preferencia de
  arquitectura: un cliente solo tiene socket abierto contra el host, así que el
  ping de los demás no lo puede saber ni aproximar. Se lee de ENet
  (`PEER_ROUND_TRIP_TIME`), que ya lo mide para su control de flujo — un eco
  propio sería medir dos veces lo mismo y peor. Con Steam (R2) devuelve «no se
  sabe» en vez de inventar un cero.
- **Los nombres se sanean AL RECIBIRLOS**, porque llegan de otra máquina: un
  salto de línea parte la fila en dos y un nombre de 4 kB empuja el ping fuera de
  la pantalla. Y el nombre de fábrica es el de la sesión del sistema operativo,
  no «Marinero»: con el segundo, las dos ventanas del ciclo de trabajo se llaman
  igual y la lista no sirve para lo único que tiene que servir.

**Consecuencias:** `Net` gana `desconectar()` —la salida limpia que faltaba: solo
se salía de la red por accidente o cerrando el proceso— y una clase pura más
(`NetTripulacion`). El menú de pausa y la portada comparten `EstiloMenu`, que es
la regla 11 aplicada al color y al margen. Queda pendiente que cambiar el nombre
con la partida abierta reetiquete (hoy solo viaja al entrar) y que la lista diga
también quién está en qué estación. `tests/partida_tests.tscn` (56 checks).

## Plantilla para decisiones nuevas

```
### <fecha> — <título corto>
**Contexto:** qué problema o encrucijada había.
**Decisión:** qué se eligió.
**Por qué:** el motivo real, incluidas las alternativas descartadas.
**Consecuencias:** qué queda atado por esta decisión, qué deuda crea.
```
