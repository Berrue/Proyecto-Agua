# Pesca: tiers de pez, tiers de caña y el camino a «más peces, más rápido»

Estado: **implementado** (tiers + ventana de reacción + cañas), salvo lo marcado
como pendiente. La matemática vive en `game/fishing/fight_model.gd`, la tabla de
especies en `game/fishing/fish_species.gd`, las cañas en `game/fishing/rod_tier.gd`
+ `resources/rod_tiers/*.tres`. Tests: `tests/fishing_tests.tscn`.

## 1 · La ventana de reacción (el fix del playtest)

La queja: «el sedal se rompe demasiado rápido». El diagnóstico: la rotura exigía
sostener la sobrecarga solo **0,5 s, igual para todos los peces** — con el mar
moviendo la borda, entre el chirrido y el snap no daba tiempo físico a soltar el
clic. Eso viola la regla 8 (todo fallo se telegrafía ANTES de castigar: avisar
sin dar tiempo de reaccionar no es avisar).

El arreglo NO es bajar la tensión del juego: es hacer la ventana **proporcional
a la escuela**. La sobrecarga sostenida que exige el snap ahora la fija el tier
del pez (`FightModel.SNAP_HOLD_BY_TIER`), y la caña montada puede sumar gracia:

| Tier | Peces | Ventana de sobrecarga |
|---|---|---|
| 1 (banda A) | Sardina, Caballa, Jurel | **1,5 s** (antes 0,5) |
| 2 (banda B) | Lubina, Bacalao, Fletán | **1,0 s** |
| 3 (banda C) | Atún | **0,65 s** |
| 4 (legendaria) | Aguja azul | **0,45 s** |

El que aprende con sardinas tiene margen real para leer el aviso y soltar; el
que pelea la legendaria ya entrenó los reflejos con toda la escalera. Bajar de
~0,45 s convertiría la rotura en un robo — ese suelo es deliberado y está
comentado en la constante. El resto de la fórmula (aviso al 80 %, chirrido desde
el 70 %, un pico de un frame jamás rompe) no cambia.

## 2 · Tiers de pez (16 especies: el doble por banda)

**El tier ES la banda hecha número** (1=A, 2=B, 3=C, 4=legendaria): el pez del
mar bravo es el pez difícil, que es la tesis del juego. No hay un segundo eje de
dificultad escondido: `pull` (fuerza del tirón) ya escala dentro de cada banda,
y el mar pone el resto vía `SEA_K · |aceleración de borda|`. La 2ª tanda
duplicó cada banda (6/6/2/2, protegido por test) SIN mover ninguna especie de
sitio: la tabla se indexa por posición desde tests y capturas ajenos, así que
**solo se añade al final** — el orden del archivo no es el orden de la escalera.

| Pez | Furia | Tier | Peso | Pull | Valor | Nota |
|---|---|---|---|---|---|---|
| Boquerón | 1,5+ | 1 | 1 kg | 0,26 | 5 | el más humilde |
| Sardina | 0+ | 1 | 2 kg | 0,28 | 6 | pica generosa, escuela |
| Faneca | 1,5+ | 1 | 2 kg | 0,31 | 8 | |
| Caballa | 0+ | 1 | 3 kg | 0,34 | 8 | |
| Jurel | 0+ | 1 | 4 kg | 0,38 | 8 | |
| Sargo | 2+ | 1 | 4 kg | 0,40 | 14 | el techo de la banda A |
| Dorada | 3+ | 2 | 5 kg | 0,42 | 28 | |
| Lubina | 3+ | 2 | 8 kg | 0,45 | 35 | lucha real |
| Merluza | 3+ | 2 | 10 kg | 0,50 | 40 | |
| Bacalao | 3+ | 2 | 12 kg | 0,55 | 45 | |
| Fletán | 4+ | 2 | 20 kg | 0,64 | 90 | mañana: exige 2 personas (DISENO §3) |
| Congrio | 5+ | 2 | 26 kg | 0,68 | 130 | el matón de la B, puente a la C |
| Mero | 6+ | 3 | 45 kg | 0,74 | 320 | abre la pesca heroica |
| Atún | 6+ | 3 | 60 kg | 0,80 | 450 | |
| **Aguja azul** | 7+ | 4 | 110 kg | 1,00 | 800 | legendaria |
| **Marrajo** | 7,5+ | 4 | 160 kg | 1,05 | 900 | legendaria: el tiburón |

Detalles que importan:

- **Solo los tres comunes con modelo autorado (Sardina/Caballa/Jurel) tienen
  `min_fury` 0**: en furia ≤1 el sorteo es EXACTO a ellos (invariante de
  `fish_asset_tests` — la calma jamás enseña un pez-cápsula). Las caras nuevas
  de banda A entran con el mar ya picado (furia 1,5-2).
- Las legendarias usan `rarity 0.15` cada una: con DOS en el pool, la SUMA
  queda en ~1 de cada 15-17 lances en su furia (banda 12-20 del diseño).
- Los pesos de las especies viejas están fijados por `bodega_tests`
  (manifiesto de bodega): se pueden añadir peces, no retocar esos kg alegremente.
- **Pendiente**: legendarias también durante la retirada pre-tsunami (necesita
  que `FishSpecies.choose` consulte el evento en `Ocean`) y nombre en bitácora.

## 3 · Tiers de caña

`RodTier` (Resource, mismo patrón que los tiers de tsunami) con tres `.tres` en
`resources/rod_tiers/`. La escalera es la rama APAREJOS del árbol de mejoras
(DISENO §3); comprarlas será cosa de la lonja cuando exista el inventario.

| Caña | Sedal (tensión) | Carrete (velocidad) | Gracia extra | Alcance | Se ve |
|---|---|---|---|---|---|
| Iniciación | ×1,0 | ×1,0 | +0,0 s | ×1,0 | empuñadura negra |
| Faena | ×1,3 | ×1,2 | +0,25 s | ×1,15 | empuñadura verde |
| Altura | ×1,6 | ×1,45 | +0,5 s | ×1,3 | empuñadura latón |

Principios que la implementación respeta:

- **Puerta blanda, jamás candado.** Ninguna caña «desbloquea» peces: con la de
  iniciación PUEDES clavar un atún, y la física (su tirón contra la capacidad
  real de tu sedal) hará la captura casi imposible — pero honesta. Perderlo pide
  mejor aparejo; no hay cartel de «necesitas nivel 3». Cortar/soltar ante el
  aviso sigue siendo la decisión que duele (rol APAREJOS, DISENO §2).
- **El feedback se normaliza contra TU sedal.** Chirrido, ámbar→rojo, barra y
  rumble leen `tension / max_tension()` del aparejo montado: con caña mejor el
  mismo tirón chirría menos porque de verdad está más lejos de romper. El
  chirrido dice «cerca de TU límite» — la regla 8 aplicada a la tienda.
- **Piezas, no «+5 %».** Cada tier se ve (hoy: color de empuñadura; mañana: su
  modelo) y se siente en tres sitios concretos: aguanta más, recoge más rápido,
  perdona más. La T1 es la base neutra: la caña que ya estaba afinada.
- **Cambiar de caña en plena lucha está prohibido** (los números se copian al
  clavar): sería trampa y desincronizaría el feedback.

Probar en el toybox: tecla **C** (HUD de debug) cicla la escalera con la caña en
reposo; la línea CAÑA del HUD muestra cuál llevas montada.

## 3b · Revisión de balance (2ª pasada, con las 16 especies)

Lo que se revisó al duplicar la plantilla, y el veredicto de cada número:

**Pull — escalera sin solapes (test `la escalera de pull no se solapa`):**
A 0,26-0,40 · B 0,42-0,68 · C 0,74-0,80 · L 1,00-1,05. Ningún pez de una banda
tira más fuerte que uno de la siguiente: la ventana de reacción por tier jamás
contradice lo que el sedal siente. Dentro de cada banda el pull sube en pasos
de ~0,03-0,06 — hay progresión interna sin necesitar más tiers.

**Cañas — el umbral de codicia** (recoger EN el tirón: tensión ≈ pull + 0,55
con el pez fresco, más el mar). Con qué pez te parte la codicia en calma:

| Caña | Capacidad | La codicia rompe desde… | Zona relajada (hold-clic sobrevive) |
|---|---|---|---|
| Iniciación | 1,0 | Lubina (0,45) | banda A |
| Faena | 1,3 | Atún (0,80)* | banda B baja (el mar de su furia lo vuelve a poner serio) |
| Altura | 1,6 | Marrajo (1,05) | hasta banda C en calma — pero la C no vive en calma |

\* El mero (0,74) queda a un 1 % del límite de la Faena en calma absoluta; su
mar real (furia 6+, +0,36-0,6 de tensión) lo remata siempre. Es la puerta
blanda funcionando: los números de las cañas se quedan como están.

**Ventanas de sobrecarga — revisadas y mantenidas.** La cifra que importa es la
**ventana EFECTIVA con la caña que le toca al pez** (tier del pez + gracia de
la caña):

| Emparejamiento | Ventana del pez | + gracia | Efectiva |
|---|---|---|---|
| Banda A + Iniciación | 1,5 s | +0,0 | **1,5 s** |
| Banda B + Faena | 1,0 s | +0,25 | **1,25 s** |
| Banda C + Altura | 0,65 s | +0,5 | **1,15 s** |
| Legendaria + Altura | 0,45 s | +0,5 | **0,95 s** |

Bien emparejado, la ventana nunca baja del segundo: la escalada de exigencia
real es suave (1,5 → 0,95). Las ventanas cortas a pelo (0,65/0,45) solo se
sufren pescando POR ENCIMA del aparejo — que es exactamente el mensaje.

**Duda abierta (anotada, no bloquea):** el boost «de tu furia» del sorteo decae
pasados `min_fury + 3`, así que en furia 9-10 el atún pesa como una sardina en
el sorteo y las legendarias se rarifican (~1/38). En el rango jugable de
tormenta (7-8,5) los números cuadran; revisar cuando exista la furia sostenida
9-10 real (retirada/post-tsunami).

## 4 · «Más peces, más rápido»: el plan de escalado

La promesa de la progresión es exactamente la petición del playtest: facilitar
el TRABAJO de pescar sin borrar el verbo. Orden aproximado de entrada, alineado
con la rama APAREJOS (caña → red con chigre → nasas → palangre, cada arte una
estación) y con las reglas del árbol (piezas visibles, nada de +5 % ocultos,
toda mejora mayor añade una estación):

1. **Ya entregado — la escalera de cañas.** Más sedal = peleas bandas altas con
   dignidad; más carrete = cada captura tarda menos; banda baja con caña alta ≈
   trivial: farmear sardinas mirando al amigo se vuelve literal.
2. **Ya entregado — el soporte de borda** (`SoporteCania`, uno por banda en los
   sockets `Gear*`; nació en la fase B de [PORTEO.md](PORTEO.md)). Clavas la
   caña con `E` y **pesca sola**: espera, toques falsos y mordisco siguen
   corriendo, el soporte es su cuerpo visible (recibe el muelle REAL de la caña
   vía `set_doblado`, así que la señal no puede mentir — regla 8) y el sedal
   sale de su punta. Los canales de primera persona (rumble, kick de FOV, flash
   del HUD) se apagan mientras no la sostienes: el aviso pasa a ser del mundo
   (chomp 3D en la boya, «!» flotando sobre ella, la caña doblándose en la
   borda). Retomarla con `E` dentro de la ventana ES el minijuego de haberla
   dejado sola. De paso resuelve el conflicto caña↔manos llenas.

   **Lo que multiplica es tu tiempo, no las capturas** (matiz que corrige la
   versión anterior de este plan): con una caña sigues sacando un pez por
   ciclo — lo que ganas es convertir los 8-25 s de espera en achique, estiba o
   porteo. El multiplicador de piezas de verdad llega con el cebo (paso 3) y la
   red (paso 4); en coop, con las dos bandas caladas, sí escala por tripulante.

   *Corrección de balance al integrarlo (2026-08-23):* la ventana de picada era
   1,8 s la sostuvieras o no, y medida contra la cubierta real hacían falta
   ~2,1 s solo para reaccionar, cruzar 4,74 m, apuntar y retomar — la caña
   clavada pescaba sola *para que el pez se te fuera siempre*. Ahora
   `BITE_WINDOW_SOPORTE` = **3,5 s** cuando está clavada (1,8 s en la mano),
   con el margen protegido por test contra la geometría del barco. Lo sostiene
   la física de un *rod holder* real: el pez engancha contra una caña amarrada
   que no cede y eso lo clava a medias solo.
3. **Ya entregado — el cebo** (`TipoCebo` + `resources/cebos/*.tres`, el cubo en
   `game/props/cubo_cebo.tscn`). Es el primer multiplicador de PIEZAS de
   verdad. Ver §5 para el detalle.
4. **Diseñada — la red de levante con chigre** ([CHIGRE.md](CHIGRE.md), sin
   código aún). El arte de volumen PARA DOS: estación guía (pescante, mantiene
   la boca alineada) + estación chigre (vira), acopladas por una sola tensión
   de cable. El «de a 2» lo impone la física, no un candado (la regla DRG del
   DISENO se respeta: solo funciona «lento y feo» únicamente en calma). Dos
   correcciones sobre lo que decía este plan: captura **piezas reales**
   (8-14 rigidbodies por lance — la bodega cuenta presencia física), no «kg
   por lance»; y **ya no depende del break-force artesanal** — la rotura vive
   en un `LanceModel` puro (patrón FightModel), los joints eran de la
   solución descartada. División de artes: la red paga CUOTA (banda A-B baja),
   la caña paga MONEDAS y todo tier 3+.
5. **Nasas** (pasivo): se calan al salir, se recogen al volver — pescan mientras
   pescas. Volumen bajo pero gratis en atención; premia planificar la ruta.
6. **Palangre** (pasivo mayor, endgame de volumen): línea madre con N anzuelos,
   calar y virar son estaciones; convierte una salida entera en logística de
   tripulación.
7. **Sonar T2/T3 y bancos**: el banco del día (especie ×2, ya en DISENO §4) +
   sonar que lo LOCALIZA — más peces por saber DÓNDE, que es progresión de
   información, la especialidad de la casa.

Lo que NO se hará: auto-pesca que juegue la lucha sola (el tira-y-afloja es el
minijuego; lo pasivo pesca VOLUMEN anónimo, jamás el pez gordo), y
multiplicadores invisibles. Si un arte no se ve en el barco, no entra.

## 5 · El cebo

`TipoCebo` (Resource, como `RodTier`) con dos `.tres` en `resources/cebos/`, y
el **cubo** (`CuboCebo`) como pieza física en cubierta, a babor entre la bodega
de popa y los soportes de caña. Es **mobiliario, no una mejora**: el cubo
siempre está a bordo; lo que se compra en puerto es lo que lleva dentro (el
sink de DISENO §3).

| Cebo | Espera | Sesgo | Qué compra |
|---|---|---|---|
| *(a pelo)* | ×1,0 | 0 | nada — y siempre es una opción válida |
| Masilla de sardina | ×0,7 | 0 | solo tiempo: un 30 % más de ciclos por salida |
| Cebo vivo | ×0,5 | 1,0 | el doble de ciclos **y** atrae a la pieza buena |

**La regla que el cebo no puede romper: compra atención, jamás peces que el mar
no da.** El sesgo NO sube la banda — entra multiplicando la misma «cercanía a
tu furia» que ya decide el sorteo, así que con el mejor cebo en calma siguen
picando sardinas, y en furia 5 no aparece un atún. Sumar furia falsa habría
sido más fácil y habría vendido la tesis del juego (*el pez caro vive donde el
mar es peor*) en la lonja, igual que el sonar vende precisión pero nunca
justicia. Dos tests lo protegen, uno por banda. *(Esto corrige el «sube un
escalón la banda del sorteo» que decía la primera versión de este plan.)*

**El ciclo.** `E` en el cubo llena el anzuelo con `CEBO_CARGAS_MAX` = 6
picadas; cada picada se come una carga **la subas o te la roben** — que perder
un pez cueste también el cebo es lo único que hace de gastarlo una decisión.
Seis y no una para que cebar sea un ritmo (vuelves al cubo cada tantos peces,
como a la bodega) y no una tarea por lance. Cambiar de cebo tira lo puesto: no
se mezclan masilla y cebo vivo en el mismo anzuelo.

**Lo que se ve** (regla del árbol: piezas, no «+20 %»): el nivel del balde baja
con lo que queda y se tiñe del color del cebo, el prompt al mirarlo dice qué
hay, cuánto queda y qué hace, y la línea CAÑA del HUD de debug lleva el cebo
puesto y sus cargas. Nadie abre un menú para saber si hay cebo a bordo.

**Pendiente:** comprarlo en puerto (necesita la lonja) y su sonido al cebar
(política ElevenLabs, regla 10). Hoy el cubo arranca con 24 cargas de masilla.

## Historial

- 2026-08-23 — creado: ventana de reacción por tier (fix del playtest «rompe
  demasiado rápido»), tiers 1-4 en la tabla de especies, Aguja azul legendaria,
  escalera de cañas `RodTier` ×3, tecla C en el HUD de debug, y este plan.
- 2026-08-23 (2ª tanda) — el doble de peces: 16 especies (6/6/2/2 por banda,
  solo añadiendo al final de la tabla), Marrajo como segunda legendaria
  (`rarity` 0,2 → 0,15 cada una para que la suma siga en 1/12-20), y revisión
  de balance (§3b): pull sin solapes entre tiers, cañas y ventanas mantenidas
  tras el análisis de emparejamientos.
- 2026-08-23 (5ª tanda) — paso 4 **diseñado**: la red de levante con chigre,
  pensada a fondo en [CHIGRE.md](CHIGRE.md) (petición: «que tenga que usarse
  de a 2» — resuelto por física, sin candado). Sin código: DISENO corta la
  red del slice (fase 2+), el plano queda listo.
- 2026-08-23 (4ª tanda) — paso 3: **el cebo** (§5). `TipoCebo` con masilla y
  cebo vivo, el cubo como pieza de cubierta con nivel visible, `E` para cebar
  (6 picadas por cebada, una carga por mordisco), y el sesgo que atrae a la
  pieza buena **sin** subir de banda — con dos tests custodiando esa regla.
- 2026-08-23 (3ª tanda) — paso 2 del roadmap cerrado: el soporte de borda ya
  venía de la fase B del porteo, así que aquí se **verificó** (55/55 en
  `porteo_tests`), se corrigió su balance (`BITE_WINDOW_SOPORTE` 3,5 s frente a
  los 1,8 s que hacían la promesa imposible, con test contra la geometría real
  del barco) y se ajustó lo que el plan prometía: el soporte multiplica tiempo
  útil, no piezas.
- 2026-08-23 (6ª tanda) — **la caña se rehízo como arte propio** (referencia: una
  captura de otro juego que trajo el usuario — caña naranja, anillas, carrete a
  la vista). Deja de ser dos cilindros y una esfera: `tools/build_fishing_rod.py`
  genera `game/fishing/models/cania.glb` (cuerpo naranja en dos tramos, seis
  anillas escalonadas + puntera, portacarretes negro y cromo, y un carrete de
  spinning con bobina, arco y manivela), documentado en
  `source_assets/fishing/README.md`. Dos decisiones que cambian lo de antes: el
  color del tier pasa a la empuñadura **delantera** (la trasera se la traga la
  cápsula del brazo del viewmodel, o sea que la mejora se pintaba donde no se
  ve), y la caña **rueda 50°** sobre su eje en el viewmodel
  (`FishingRod.model_roll_deg`) para que el carrete asome por la izquierda del
  brazo en vez de quedar detrás de él. `ReelRotor` y `ReelHandle` salen del GLB
  con el origen en su eje de giro: girarlos al recoger es ya solo cablear.
  Pendiente para que la caña se parezca del todo a la referencia: que el cuerpo
  se **curve** al pelear en vez de inclinarse rígido (hoy `_bend` gira el pivote
  entero).
- 2026-08-23 (7ª tanda) — **la caña se dobla de verdad**. El cuerpo lleva rig:
  seis huesos (`CaniaRig` en el GLB) y pesos calculados en el script, y el
  doblez `_bend` —la misma señal de tensión de siempre— se reparte entre dos
  gestos que un pescador distingue: la caña entera inclinándose
  (`BEND_RIGID_SHARE`) y el cuerpo arqueándose, con el arco cargado hacia la
  punta (`BEND_BONE_WEIGHTS`, acción rápida). Lo que hace que esto no sea
  adorno: **el nodo `Tip` lee la posición del último hueso**, así que el sedal
  sigue naciendo de la punta real y no de una copia de la curva en CPU — nada
  que se pueda desincronizar en silencio (regla 3 aplicada a la presentación).
  Si el modelo llegara sin rig, la caña vuelve sola al doblez rígido de antes.
  Se mira con `tests/capture_cania.tscn` (cinco niveles clavados a mano, porque
  en partida el máximo no dura lo bastante para juzgarlo).
