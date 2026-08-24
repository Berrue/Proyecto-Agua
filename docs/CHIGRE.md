# El chigre y la red de levante — pesca de volumen para dos

Estado: **DISEÑO, sin código** (2026-08-23). Es el paso 4 del roadmap de
[PESCA.md](PESCA.md) §4, pensado a fondo antes de construirlo. Ojo con el
nombre: [RED.md](RED.md) es el *networking*; esto es la red DE PESCAR, y el
doc se llama como su estación (el patrón de BOMBA_MANUAL.md) para no chocar.

La petición que lo origina: **«estaría bueno que tenga que usarse de a 2»**.
Este documento diseña exactamente eso — y resuelve el choque frontal que esa
petición tiene con una regla cerrada del DISENO (§3, abajo).

## 1 · Qué es y qué NO es

**Una red de LEVANTE**: se cala por la borda con un pescante, se deja armar
bajo el agua, y se vira con el chigre. No es cerco ni arrastre — esas artes
exigen un barco que navega, y el barco navegable sigue pendiente. Cuando
navegue, el arte puede evolucionar; el tango de dos que se diseña aquí no
cambia.

**La división de artes que lo sostiene** (y que mantiene viva a la caña):

| Arte | Paga | Piezas | Quién |
|---|---|---|---|
| La caña | **MONEDAS** (pieza a pieza, el clímax) | todas las bandas, tiers 3+ y legendarias SOLO aquí | 1 persona |
| La red | **CUOTA** (kg a granel) | banda A y B baja; tier 3+ JAMÁS entra | 2 personas |

La economía ya es doble (DISENO §3: kg de cuota + monedas por especie); cada
arte cobra en una moneda. La red no sustituye a la caña ni en dinero ni en
gloria: la sardina a granel llena la bodega, el fletán y el atún siguen
siendo una historia personal con caña. Y no es pasiva — eso serán las nasas
y el palangre; la red es el verbo ACTIVO de volumen.

## 2 · El tango: dos estaciones, una sola verdad

**Estación GUÍA (el pescante, en la borda).** Sostiene la BOCA de la red
abierta y alineada contra la deriva con A/D — el mismo músculo que la caña
ya entrenó con la contra. Ve lo que el del chigre no ve: el copo llenándose,
la boca cruzándose, la sombra de «algo grande». Decide cuándo cerrar.

**Estación CHIGRE (el tambor, centro de cubierta, socket `Winch`).** Cala
(suelta cable) y vira (mantener clic recoge, con el trinquete sonando). Es
la fuerza; el guía es la información — la misma división CUBIERTA/CABINA
del diseño de roles.

**El acople es una sola tensión** (regla 8: el feedback jamás miente):

```
tensión_cable = carga(kg en el copo)
              + K_ALINEO · |desalineo de la boca|
              + SEA_K · |aceleración de borda|      (la MISMA del sedal)
              + K_VIRADA · velocidad de virada
```

Virar con la boca cruzada = tensión alta y avance casi nulo. Guiar sin que
nadie vire = el copo se hunde y va soltando pescado (el espejo del sedal
flojo). Cada estación oye/ve SU mitad (el trinquete y el crujido en el
chigre; la boca y el agua en el pescante) y la conversación — «¡para!»,
«¡endereza!», «¡AHORA!» — es la mecánica. El audio como mecánica, no
ambientación: ya era dependencia crítica del diseño.

## 3 · «De a 2» sin romper la regla de DRG

DISENO §2 tiene un «hard no» **cerrado**: *interdependencia por eficiencia,
jamás por candado — todo lo completa 1 persona lento y feo*, con el «chigre
elástico (1×/1,8×/2,4×/2,8× con 1-4 manos)» como ejemplo. Un cartel de
«se necesitan 2 jugadores» lo violaría de frente.

La resolución: **la física es la puerta, como en las cañas.** El desalineo
de la boca crece solo con el oleaje (sale de `Ocean`, gratis). El avance de
la virada solo cuenta con la boca dentro de umbral. Entonces:

- **A 2** (guía + chigre): el tango fluye — «rápido y con estilo».
- **A 1**: ping-pong entre estaciones. En furia ≤1 el mar mueve poco la
  boca: da tiempo a cruzar la cubierta y virar unos segundos — funciona
  «lento y feo», ~⅓ del rendimiento y con la tensión siempre rozando. En
  furia 3+ (donde el volumen PAGA), el desalineo crece más rápido que el
  viaje entre estaciones: virar en solitario es regalarle la red al mar.
- **A 3+**: manos extra al tambor (la manivela doble clásica) aplican la
  curva elástica del DISENO a la velocidad de virada.

El dial de furia que ya gobierna todo hace que el «de a 2» apriete
exactamente donde la red importa — sin popup, sin candado, sin números
artificiales. Si aún así se quisiera el candado DURO (dos presencias
obligatorias por diseño), hay que revertir una decisión cerrada del DISENO y
anotarlo en DECISIONES; este diseño no lo necesita.

## 4 · El lance, de principio a fin

1. **Calar (~5 s, ambos).** El guía abate el pescante fuera de borda; el
   chigre suelta cable. Splash grande, la boca abierta se ve bajo el agua.
2. **Armar (10-40 s, la decisión).** La red se llena del cardumen de la
   furia actual. Más tiempo = más kg = más tensión luego: el MISMO dial de
   codicia de toda la pesca. En furia 6+, riesgo telegrafiado de «algo
   grande» (§5). El guía lo ve llenarse; cerrar es su llamada.
3. **Virar (15-30 s, el tango).** Lo de §2. La ventana de sobrecarga es
   generosa (~1,2 s sostenida — es un arte pesado, tier «industrial»), y
   SIEMPRE telegrafiada: crujido de fibras + cable ámbar→rojo, los avisos
   que el jugador ya sabe leer.
4. **Volcar.** El pescante gira a bordo y la boca se abre: **una montaña de
   peces REALES cae en cubierta**. Ese es el premio-imagen del arte — y el
   trabajo que reparte: estibarlos es la tarea n−1 de la calma, el porteo
   existe para esto. La ola puede barrer lo no estibado: el botín sigue en
   riesgo hasta la bodega, como manda el diseño.
5. **Si rasgó**: remendar (§6).

## 5 · La captura: peces de verdad, a granel

- **8-14 piezas reales por lance lleno** (rigidbodies con su especie, peso y
  valor), del pool de la furia actual **filtrado a tier ≤ 2** y sesgado a
  cardumen (banda A pesa el doble en este sorteo; la red no elige).
- **Por qué piezas y no «kg abstractos»**: la bodega cuenta presencia física
  (PORTEO, principio 5) — un número flotante mentiría; la montaña de peces
  es la comedia central del friendslop; y 12 cuerpos están dentro del
  presupuesto (los tests ya spawnnean 12 barriles sin despeinarse).
- **Tier 3+ no entra JAMÁS**: un atún no cabe en una red de levante — la
  ROMPE. En furia 6+, durante el armado, «algo grande» puede embestir la
  red: tirón sordo + el cable dando bandazos (telegrafía), y si no se vira
  en la ventana, rasga el copo. La red en aguas heroicas es una apuesta;
  esas aguas son de la caña. La frontera entre artes la traza el mar.
- **Bycatch cómico** (idea barata, fase D): una bota, un alga gigante — a
  cubierta con su thud. DREDGE lo hizo religión; a nosotros nos vale la
  risa y el splash.

## 6 · Rasgar y remendar

Sobrecarga sostenida → **RASGA**: el copo se abre bajo el agua, los peces
escapan en una nube de splashes (pérdida VISIBLE, permanencia del fallo), y
la red queda colgando hecha jirones — el compañero que llega de la bodega VE
qué pasó sin que nadie se lo cuente. La red dañada no pesca: **remendar** en
la borda (E sostenido ~20 s, interrumpible — en plena subida de furia esos
20 s son una decisión), o pagar reparación en puerto (el sink de siempre).
Sin minijuego de remiendo en v1; hueco declarado para después.

## 7 · Números iniciales (para el playtest, no para la piedra)

| Knob | Valor inicial | Por qué |
|---|---|---|
| Piezas por lance lleno | 8-14 | montaña visible sin reventar físicas |
| Tiempo de armado a tope | ~35 s | un lance entero ≈ 60-90 s |
| Ventana de sobrecarga | 1,2 s | arte pesado: más gracia que la caña (0,45-1,5) |
| Desalineo: deriva | escala con oleaje local (`Ocean`) | el mar es el dial; furia baja perdona el solo |
| Umbral de boca alineada | ±25° | ancho: el tango debe fluir, no ser un pixel-hunt |
| Rendimiento 2P objetivo | ~3-4× piezas/min vs 2 cañas en banda A | volumen claro, sin volver tonta a la caña |
| Valor medio del lance | ~30-60 monedas + 20-40 kg | paga CUOTA; el lujo sigue en la caña |
| «Algo grande» | solo furia ≥ 6, telegrafiado ≥ 3 s | frontera de artes visible y justa |

## 8 · La costura técnica (por qué es barata)

- **`LanceModel` puro** (patrón `FightModel`, RefCounted): entradas por tick
  (virando sí/no, alineo del guía, `sea_accel`, dt) → estado (kg, progreso,
  tensión, desalineo, rasgada). Testeable headless con dos streams de input
  — el «tango de a 2» se prueba sin teclas ni red.
- **Cero joints.** Cable y copo son PRESENTACIÓN (ImmediateMesh como el
  sedal; péndulo simple al izar). El break-force artesanal que la review
  (hallazgo 6) daba por prerequisito del chigre **deja de ser dependencia**:
  la rotura vive en el modelo, no en la física.
- **En red** (la otra red): el modelo corre en el HOST; cada estación manda
  su input (2 números pequeños) y vuelve un estado de ~4 números — cabe en
  el goteo de 10-20 Hz de R0. Las estaciones capturan input como la lucha
  (`input_captured`, precedente hecho). Para jugarlo a 2 máquinas hace
  falta el porteo en red (R1) por el volcado de peces; el modelo no lo
  necesita para existir y testearse.

## 9 · A bordo (las piezas se ven)

- **El chigre** en el socket `Winch` (ya reservado): tambor + manivelas que
  GIRAN con la virada real. Desatendido con carga, traquetea — la
  señalización diegética de estación que manda el diseño.
- **El pescante** en una borda. Propuesta: al comprarse, SUSTITUYE el
  soporte de caña de esa banda — el espacio de cubierta es finito, la
  compra se ve, y elegir borda es elegir cómo pescas. ABIERTA con quien
  lleve el barco (los sockets `Gear*` ya se declaran «caña, soporte, red o
  nasas»).
- **La red plegada** visible en la borda cuando no se usa; **rasgada se ve
  rasgada** hasta que alguien remiende.

## 10 · Fases

- **A — El modelo.** `LanceModel` + tests headless: el tango avanza solo
  con ambos inputs; solo-ping-pong rinde ~⅓ en furia 1 y ~0 en furia 4;
  sobrecarga telegrafiada antes de rasgar; composición tier ≤ 2; «algo
  grande» solo furia 6+.
- **B — Las estaciones.** Chigre y pescante en el barco, input capturado,
  feedback (trinquete, crujido, cable de color). Para validar en solitario:
  **guía fantasma en el HUD de debug** (un deslizador que hace de segundo
  jugador — la tradición del dios de la furia).
- **C — A dos máquinas.** Sobre R0/R1 de [RED.md](RED.md): inputs por
  estación, modelo en host, volcado replicado.
- **D — Economía.** Compra en lonja (rama APAREJOS), remiendo con costo,
  bycatch, balance de cuota con telemetría.

Nota de prioridad: DISENO §5 corta red/chigre del slice (fase 2+). Este doc
deja el plano listo; construir A-B cuando se decida es implementación, no
diseño.

## 11 · Preguntas abiertas

1. ¿Ayuda de solo comprable (un «tensor» que sujeta la boca a medias) para
   el modo 1 jugador, o solo puro lento-y-feo? El diseño funciona sin ella.
2. ¿El pescante sustituye el soporte de caña de su borda (propuesta §9) o
   pide socket nuevo del barco modular?
3. ¿Remiendo como minijuego (fase 2+) o siempre E sostenido?
4. Con barco navegable: ¿arrastre corto como arte nueva o evolución de esta?
5. El volcado sobre cubierta con 6 jugadores estorbando: ¿hace falta zona de
   volcado sugerida, o el caos ES el juego? (Playtest.)
