# El puesto de timón, el motor y la nafta

**Estado: PLAN (24-ago-2026). Sin una línea de código todavía.**

Fuente: la investigación «Puesto de Timón» (artifact
`claude.ai/code/artifact/93f2b125-fbd1-42ec-9df1-3160b5ee1d57`, 24-ago-2026,
formulada sobre este árbol de trabajo). Este doc la condensa ENTERA —el artifact
es compartido y a otra sesión le cuesta leerlo— y le añade lo que la
investigación no traía: **el sistema de nafta**, con las decisiones tomadas con
el diseñador el 24-ago-2026.

---

## 0 · Las decisiones cerradas (24-ago-2026)

| Decisión | Qué se decidió | Por qué |
|---|---|---|
| **Nafta real, tanque holgado, aguja diegética** | El motor consume nafta según el telégrafo; el tanque sobra para una salida normal; la aguja vive en la consola del puesto, no en HUD | Revisa DISENO §3 («nunca medidores dentro de la run»). El tedio que DREDGE cortó era la *gestión constante*; un tanque holgado convierte la nafta en una decisión POR SALIDA. Y la factura de diésel por distancia no se pierde: **se convierte en factura por litros repostados** — el mismo sink de 15-25 %, ahora físico y honesto |
| **Quedarse seco puede pasar** | Aguja baja → el motor tose (reserva) → muere. Sin hélice no hay estela ni golpe de máquina: gobierno residual (la pala solo muerde con arrancada u olas) | Regla 8: telegrafiado dos veces antes de castigar. La salida es el bidón estibado — o quedar al garete, que con el parte encima es la anécdota que el juego busca |
| **Telégrafo con muescas** | Palanca visible: atrás toda · atrás · stop · poca · media · avante toda | Diegético y legible para TODA la tripulación de un vistazo, y hace legible el consumo: avante toda bebe el doble. DISENO §2 ya nombraba «telégrafo del motor» en la estación TIMÓN |
| **La llave arranca el motor** | Sin `LlaveMotor` insertada en el puesto, el motor no arranca | El objeto ya existe (`game/props/llave_motor.tscn`, se hunde, índice 2 de NetPorteo) y activa la misión de rescate emergente ya diseñada en DISENO §2. Contenido casi gratis |
| **Tanque fijo + bidones portables** | Tanque en máquinas; bidones `Portable3D` estibados en bodega, compiten por espacio con el pescado. Repostar = porteo del bidón a la boca de llenado | Autonomía vs botín es una decisión de estiba real. Usa porteo y estiba ya hechos. **El bidón FLOTA** (la nafta es menos densa que el agua — honestidad física; el drama de hundirse ya lo cubre la llave) |
| **Compra: interim ahora, lonja después** | v1: tanque lleno al zarpar + recarga por HUD debug. La compra real (dinero de lonja, DISENO §3) queda diseñada en §8 pero NO bloquea este plan | La lonja necesita el inventario que otra sesión tiene en curso. Un control que todavía no existe no necesita economía |
| **Arranque por el modelo puro** | Primero `timon_model.gd`/`motor_model.gd` + arnés (archivos nuevos, cero choque); el retoque de `inertia`/`angular_drag` en `fishing_boat.tscn` se hace COORDINADO cuando aterrice el hundimiento de la sesión paralela | `floating_body.gd` está tocado en vuelo por la física de agua. El paso perceptible se retrasa un paso a cambio de no pisarse |

Cuando entre el primer commit de implementación, la revisión de DISENO §3
(medidor diegético + factura por litros) se anota en `DECISIONES.md` — la
documentación de una decisión va en el mismo commit que la implementa.

---

## 1 · La tesis física (del artifact, condensada)

**El timón no rota el barco: es una superficie sustentadora sumergida.** Todo lo
demás emerge de esa frase:

- La autoridad va con el **cuadrado del flujo** → sin arrancada no hay timón, y
  gestionar la velocidad se vuelve juego.
- El ángulo que manda es el **efectivo** (pala menos deriva) → la virada se
  auto-limita: fase de ataque y fase de asiento, sin amortiguación inventada.
- Pasados ~45° la placa entra en **pérdida** → el tope de 35° de los barcos
  reales emerge, no se decide.
- El flujo es **relativo al agua** → en mar de popa, surfeando la cara de la ola
  a la velocidad de la ola, la pala se queda sin flujo y el barco no obedece.
  Eso es el **broaching**, y es una resta (`v_punto − orbital`), no un sistema.

La descomposición es la del método MMG naval: **casco + hélice + pala**, donde
casco (plano de deriva, δ=0, a popa del centro de masas) y pala (δ del jugador,
en el extremo de popa) son LA MISMA matemática con parámetros distintos, y la
hélice aporta empuje axial (solo sumergida) más una estela que inyecta flujo en
la pala — el golpe de máquina: girar casi parado con timón a la banda y ráfaga
de motor.

Dos números del artifact que fijan expectativas: entre mar de proa y surf-riding
en mar de popa hay un **factor ~32 de autoridad** sin una línea de código que lo
decida; y la respuesta correcta al broaching es el golpe de máquina — que el
timonel tiene que aprender. Con nafta, esa respuesta ahora **cuesta litros**: el
mar de popa es la ruta rápida y la que bebe.

### La matemática completa (GDScript listo del artifact)

```gdscript
## game/boat/timon_model.gd
class_name TimonModel
extends RefCounted

## La matematica del gobierno, separada del nodo para poder testearla sin
## simular inputs ni levantar un mar. Mismo patron que `FightModel`.

# La misma que FloatingBody3D. Nunca el mismo numero en dos sitios.
const DENSIDAD_AGUA := 1000.0

## Placa plana: entra en PERDIDA sola a 45 grados. El tope de pala de 35 que
## usan los barcos reales sale de aqui.
static func cl(alfa: float) -> float:
    return sin(2.0 * alfa)

static func cd(alfa: float) -> float:
    var s := sin(alfa)
    return 2.0 * s * s

## Angulo de ataque EFECTIVO: lo que pide el jugador menos la deriva del flujo.
## El barco mira a -Z (verificado: RailBow en z=-6.2): avance -z, deriva +x.
static func angulo_ataque(pala_rad: float, flujo_local: Vector3) -> float:
    var avance := -flujo_local.z
    var deriva := flujo_local.x
    if absf(avance) < 0.01 and absf(deriva) < 0.01:
        return 0.0
    return wrapf(pala_rad - atan2(deriva, avance), -PI, PI)

## Fuerza de una superficie sustentadora, en ejes de MUNDO. `v_rel` es la
## velocidad de la superficie RESPECTO AL AGUA (la orbital ya viene restada);
## `eje_mecha` es el eje de giro de la pala (el "arriba" del casco).
static func fuerza_superficie(v_rel: Vector3, alfa: float, area: float,
        eje_mecha: Vector3) -> Vector3:
    var u := v_rel.length()
    if u < 0.05 or area <= 0.0:
        return Vector3.ZERO
    var incidente := -v_rel / u
    var sust := eje_mecha.cross(incidente)
    if sust.length_squared() < 1e-6:
        return Vector3.ZERO  # flujo paralelo a la mecha
    sust = sust.normalized()
    var q := 0.5 * DENSIDAD_AGUA * area * u * u
    return sust * (q * cl(alfa)) + incidente * (q * cd(alfa))
```

Sobre el **signo** de `sust`: si el barco cae a la banda contraria, se invierte.
No se razona — lo resuelve el círculo de evolución del arnés (§6), en treinta
segundos.

### La velocidad relativa — la línea que lo cambia todo

```gdscript
## En gobierno.gd
func _velocidad_relativa(punto: Vector3) -> Vector3:
    # La velocidad del PUNTO, no la del centro de masa: si el barco ya guiña,
    # la pala se mueve de lado aunque el barco avance recto.
    var v_punto := _barco.linear_velocity + _barco.angular_velocity.cross(
            punto - _barco.global_position)
    # Menos la orbital. Esta resta ES el broaching entero.
    return v_punto - Ocean.get_surface_velocity(punto) * factor_orbital
```

`factor_orbital` 0,6–0,8: la orbital de superficie decae a la profundidad de la
pala (~1 m), y de paso es la perilla de cuánto gobierno te roba el mar.

### La hélice — dos detalles que valen más que el empuje

1. **Si ventila, no empuja**: `Ocean.get_submersion(p_helice) <= 0.0 → empuje 0`.
   En mar gruesa la popa sale del agua y el motor se embala en vacío.
2. **La estela sobre la pala**: `flujo_local.z -= estela_ms * _empuje`, SIN
   sumarla a la velocidad del barco. De ahí el golpe de máquina.

La rampa (`motor_rampa_s` ≈ 2,5 s) vende la inercia longitudinal sin masa
añadida traslacional (que NO se implementa: Just Cause 3 la investigó y la dejó
fuera; cerca de la mitad de la masa el lazo diverge).

---

## 2 · Dónde va el código, y la trampa dura

**`FloatingBody3D` publica sus fuerzas ASIGNANDO `constant_force` /
`constant_torque` cada tick simulado** (para sobrevivir a `tick_divisor`). Si el
gobierno escribe esas propiedades —o usa `add_constant_force()`— la flotabilidad
se borra o el empuje se pierde según el orden del árbol, sin un solo error. La
vía del gobierno es **`apply_force()` / `apply_torque()`**: en Jolt van a un
sumador aparte que se vacía tras cada Update, conviven con `constant_force` sin
pisarla y sin depender del orden. El arnés lo custodia (test «el gobierno no
toca constant_force»).

| Archivo | Tipo | Responsabilidad |
|---|---|---|
| `game/boat/timon_model.gd` | RefCounted | Superficies: ángulo de ataque, cl/cd, fuerza. Cero nodos, cero Ocean |
| `game/boat/motor_model.gd` | RefCounted | Telégrafo (muescas → empuje objetivo), rampa, **nafta** (consumo, tos, muerte), llave. Puro y testeable |
| `game/boat/gobierno.gd` | **Node**, hijo del barco | Muestrea `Ocean`, evalúa el modelo tres veces (casco, hélice, pala) y aplica con `apply_force`. Host-only. Es `Node` y no `Node3D` a propósito: no tiene transform propio — los puntos donde empuja salen del balance, y un transform aquí sería un segundo sitio donde vive la misma posición |
| `game/boat/rueda_timon.gd` | Node3D, en `UpgradeSockets/Helm` | El puesto: agarre, rate-limit de dos etapas, telégrafo, llave, aguja de nafta, arco de mirada, trinca |
| `game/props/bidon_nafta.tscn/.gd` | `Portable3D` | El bidón: 25 l, FLOTA, se estiba en bodega, se vuelca en la boca de llenado (patrón `Zona` del gancho del farol) |
| `game/boat/gobierno_balance.gd` + `resources/gobierno/gobierno.tres` | Resource | Balance del gobierno: áreas, posiciones, coeficientes, rueda, cabo de trinca |
| `game/boat/motor_nafta_balance.gd` + `resources/gobierno/motor_nafta.tres` | Resource | Balance del motor y la nafta, **los dos en el mismo recurso**: cuánto empuja y cuánto bebe son los dos lados de la misma balanza, igual que la entrada y la salida del agua embarcada |
| `tests/gobierno_tests.tscn` | Arnés headless | §6. **Entra en la lista de CLAUDE.md en el mismo commit que lo crea** |

`Ocean` NO se toca: todo lo que el gobierno necesita ya existe
(`get_surface_velocity`, `get_height_at`, `get_submersion`, `get_breaking`).

---

## 3 · Que sea barco y no caja (anisotropía)

El mejor hallazgo del artifact: **`RigidBody3D.inertia` solo sobrescribe cada
eje si su valor es > 0** (verificado en el módulo Jolt). Se fuerza SOLO la
guiñada y se dejan cabeceo y balanceo automáticos:

```gdscript
# I_guiñada geométrica ≈ m(L²+B²)/12 ≈ 61 800 kg·m²; la inercia añadida en
# guiñada de un casco ronda 0,5-1,0× la propia → punto de partida ~95 000.
# OJO: imprimir la inercia automática real ANTES (sale de las 17 colisiones).
inertia = Vector3(0.0, 95000.0, 0.0)
```

La deriva NO se amortigua con un segundo sistema de drag (duplicaría el de las
sondas — prohibido por la regla de parametrización): la resuelve el **plano de
deriva** (`fuerza_superficie` con δ=0, ~9 m², a popa del centro de masas), que
da de una vez resistencia lateral, estabilidad direccional y el auto-límite de
la virada. Con él puesto, `angular_drag` puede bajar de 1,6 a ~0,7 y el
balanceo revive: **la única palanca del documento que mejora feel y estabilidad
a la vez**.

⚠️ Este paso edita `fishing_boat.tscn` (inertia, angular_drag) — ver §7,
coordinación.

---

## 4 · El puesto: rueda, telégrafo, llave y aguja

### La rueda — rate-limit de dos etapas

Tres retardos apilados y solo dos se tocan: suavizado de input **0 ms**
(suavizar input = mando roto), mano→rueda **4-6 s tope a tope** (el peso
mecánico, la perilla principal de carácter), rueda→pala **~2,5°/s** de servo.
`move_toward` en `_physics_process` — NUNCA `lerp` (exponencial, depende del
tick rate) ni `_process` (el bug de framerate documentado en Sailwind).

```gdscript
const VUELTA_COMPLETA_S := 5.0
const RUEDA_RATE := 2.0 / VUELTA_COMPLETA_S
const PALA_RATE_DEG := 2.5

var rueda: float = 0.0  # -1..1, lo que agarra el jugador. ESTO se replica.
var pala: float = 0.0   # -1..1, donde llegó el servo de verdad

func _physics_process(delta: float) -> void:
    var pedido := 0.0
    if _tripulada:
        pedido = Input.get_axis(&"timon_babor", &"timon_estribor")
    elif _trincada:
        pedido = _rumbo_trincado  # el cabo de trinca de DISENO.md
    rueda = move_toward(rueda, pedido, RUEDA_RATE * delta)
    pala = move_toward(pala, rueda,
            deg_to_rad(PALA_RATE_DEG) / deg_to_rad(pala_max_deg) * delta)
```

(El `delta` aquí no viola la regla 5: integra una velocidad angular cinemática,
no multiplica una fuerza.)

⚠️ **Deadzone**: el default 0,5 del InputMap mata un eje integrado. Las
acciones nuevas (`timon_babor`/`timon_estribor`, `telegrafo_subir`/
`telegrafo_bajar`) van con **0,10-0,15 + snap a cero** bajo el umbral.

**La marca de rey**: una cabilla distinta (cuero o bronce) en el radio que queda
arriba con el timón a la vía. El jugador lee el ángulo de pala de un vistazo y
cuenta vueltas viendo pasar cabillas — cero HUD, resuelve el problema que
Sailwind tiene abierto («no sé dónde está la vía»).

**El agarre**: la rueda ES el agarre del timonel (DISENO §2: no puede pescar ni
achicar). Arco de mirada limitado al agarrar, ±100° de guiñada y −35°/+25° de
cabeceo (patrón Cyclops de Subnautica) — garantiza que nunca haya un encuadre
sin horizonte ni cabina, que es la mitad del anti-mareo. Cabo de trinca: rumbo
mantenido 12 s (6 s con Hs > 6 m).

### El telégrafo — seis muescas

`atrás toda · atrás · stop · poca · media · avante toda` →
empuje objetivo −1,0 · −0,5 · 0 · +0,33 · +0,66 · +1,0, con la rampa de
`motor_rampa_s` entre medias. La palanca es un objeto visible del puesto: la
posición se lee desde la otra punta de la cubierta (información para la
tripulación, no solo para el timonel).

### La llave y el arranque

Sin `LlaveMotor` insertada, el telégrafo mueve la palanca pero el motor no
responde. Insertar la llave (porteo → interact en la cerradura del puesto) +
girar = secuencia de arranque con su audio (**ElevenLabs, regla 10**: arranque,
ralentí, tos, muerte — cada uno con su fila en THIRD_PARTY.md). La llave sigue
siendo porteable: sacarla y llevársela es apagar el barco, y perderla al agua
es la misión de rescate de DISENO §2 (se hunde).

### La aguja de nafta

En la consola del puesto, diegética (el barco es el HUD). Con el tanque holgado
mirar la aguja es una decisión por salida, no una tarea. La información de a
bordo es asimétrica a propósito: el timonel la ve; el resto ve la palanca y
oye el motor.

---

## 5 · La nafta — el modelo

Todo en `motor_model.gd` (puro) + `motor_nafta.tres` (balance). Números de
arranque para iterar, no constantes físicas:

| Perilla | Arranque | Nota |
|---|---|---|
| `tanque_l` | **45 l** | Cuadrado contra la salida tipo: 15 min a media + 20 al ralentí ≈ 20 l, o sea el **45 % del tanque**. Los 120 l del primer borrador dejaban la salida en el 15 % — la nafta no habría existido. `gobierno_tests` custodia la banda 30-60 % |
| `consumo_l_min` por muesca | stop 0,1 · poca 0,6 · media 1,2 · toda 3,0 (atrás espeja) | Al ralentí también bebe (poquísimo): apagar el motor es una decisión. **No es proporcional al empuje a propósito**: avante toda bebe 2,5× lo de media por un 50 % más de empuje, así que la ruta rápida se paga |
| `umbral_tos_l` | **6 l** | Por debajo, el motor tose: cortes breves de empuje + SFX. A consumo de media son ~5 min de aviso. La segunda telegrafía (la primera es la aguja) |
| `bidon_l` | 25 l | Medio tanque largo: devuelve la salida sin regalar un tanque nuevo. Y el bidón FLOTA |
| Recarga interim | tanque lleno al zarpar + tecla en HUD debug | Hasta que exista la lonja (§8) |

El dial completo — «una salida normal gasta entre el 30 % y el 60 % del tanque»,
«quince minutos a avante toda lo vacían», «un bidón es medio tanque largo» — está
escrito como test en `gobierno_tests`, no solo aquí: es el mismo patrón que el
balance del agua embarcada, donde el punto de equilibrio ES el dial de dificultad
y por eso no puede quedar solo en prosa.

Reglas del modelo:

- El consumo es **determinista y por tick de física** (muesca × delta), en el
  host. Nada de `Time` ni RNG.
- Tanque a cero → el motor muere (no hay «reserva automática»: la reserva ES el
  bidón, y conseguirlo es jugable). Volver a arrancar exige nafta > 0 y la
  llave.
- Repostar: el bidón en la boca de llenado transfiere `min(bidon, hueco)` a
  ritmo visible (~5 l/s) — no desaparece nafta, y con el barco escorando en
  tormenta es un minijuego de porteo gratis.
- **Sin motor no hay estela**: se pierde el golpe de máquina y el broaching no
  tiene salida — quedarse seco en mar de popa es exactamente el peligro que
  parece. La pala sigue viva con arrancada u olas (gobierno residual honesto).

Ganchos futuros anotados, NO de este plan: el motor «trucado» de DISENO §3
(+30 % y más sed), el motor que se ahoga si la celda de máquinas se inunda
(escucha a `AguaEmbarcada`), y el cuadro eléctrico («el motor viejo alimenta
solo 2 sistemas a la vez»).

---

## 6 · El arnés: `tests/gobierno_tests.tscn`

Pruebas navales estandarizadas = tests de feel repetibles. Y los fallos
silenciosos conocidos, custodiados:

1. **Círculo de evolución** con pala a tope: diámetro táctico entre 3 y 5
   esloras, y cae A LA BANDA PEDIDA (resuelve el signo de la sustentación).
2. **Zig-zag 20/20**: el overshoot mide el trabajo del timonel.
3. **Parada**: define si contra el mar se juega a posición o a reflejos.
4. **Sin arrancada**: parado y sin motor, pala a tope NO gira el barco (si
   gira, alguien metió un torque directo).
5. **Golpe de máquina**: parado, pala a tope + empuje pleno, SÍ gira.
6. **Determinismo del mando**: mismo eje crudo N ticks → mismo ángulo de pala
   (protege el rate-limiter de mudarse a `_process`).
7. **El gobierno no escribe `constant_force`/`constant_torque`** (la trampa
   dura de §2).
8. **Nafta**: consumo determinista por muesca; tos bajo umbral; a cero el
   empuje es cero; rearranque exige llave + nafta; repostaje conserva litros
   (tanque + bidón = constante); el consumo solo corre con el motor arrancado.

El arnés entra en la lista de CLAUDE.md **en el mismo commit** que lo crea (la
lista llegó a estar cinco arneses corta). Y ojo al precedente del repo: un
arnés puede salir verde con un script roto — mirar el número de checks.

---

## 7 · Fases, en orden — y la coordinación con las sesiones paralelas

El orden del artifact ponía la anisotropía primero (cero código, valida el
diagnóstico). Se **reordena una pieza** por una razón de tráfico, no de física:
`floating_body.gd` está tocado en vuelo por la sesión del hundimiento, y el
calado que esa sesión fije cambia la sumersión de hélice y pala. Releer antes
de editar; verificar que los cambios sobreviven.

| Fase | Qué | Toca | Riesgo de choque |
|---|---|---|---|
| **F1 — Modelos puros** ✅ **HECHA (24-ago-2026)** | `timon_model.gd` + `motor_model.gd` + los dos balances + sus `.tres` + `gobierno_tests` (99 comprobaciones) | Archivos NUEVOS + CLAUDE.md (lista de tests) | Cero |
| **F2 — Gobierno integrado** ✅ **HECHA (24-ago-2026)** | `gobierno.gd` colgando del barco, con las tres superficies y las pruebas navales (118 comprobaciones). **La calibración de feel queda BLOQUEADA por F2b** — ver §12 | `fishing_boat.tscn` (nodo hijo nuevo) | Bajo (fue additivo; la otra sesión metió `AguaCubierta` en el mismo archivo sin choque) |
| **F2b — Anisotropía** ⚠️ | Imprimir inercia automática real → forzar `inertia.y` → bajar `angular_drag`. El paso 1 del artifact, movido aquí | `fishing_boat.tscn` (propiedades del cuerpo) | **Coordinar**: hacerlo cuando el hundimiento de la otra sesión haya aterrizado, y recalibrar F2 después |
| **F3 — El puesto** ✅ **HECHA (24-ago-2026)** | `puesto_timon_model.gd` + `rueda_timon.gd/.tscn` en el socket Helm, cuatro acciones nuevas en el InputMap y el enganche en `portador.gd`. 157 comprobaciones. Pendiente de F3: la aguja de nafta visible y la marca de rey como pieza de arte — ver §13 | `project.godot`, `fishing_boat.tscn`, `portador.gd` | Bajo (fue aditivo) |
| **F4 — Nafta jugable** | Consumo real, tos, muerte, rearranque; `bidon_nafta` + estiba + boca de llenado; recarga en HUD debug | `game/props/`, HUD debug | Bajo (HUD debug lo tocan otros: releer) |
| **F5 — Feedback, junto** | Cadena de manos (muelles 40-60 de rigidez, saltar bajo 10 FPS), audio 3 capas + `trauma_estructural` (decae 3-8 s), ducking sidechain, FOV asimétrico (curva trauma^1,5), `set_drag()` con la aceleración lateral. **SFX por ElevenLabs** | `game/audio/`, viewmodel | Medio: el viewmodel tiene un refactor sin commitear de otra sesión |
| **F6 — Anti-mareo** | **Inclinómetro de cardán en la consola** (la pieza con evidencia experimental, p=0,005), viñeta por velocidad angular, sliders (shake, FOV, balanceo heredado, viñeta) | Puesto + `camera_feedback.gd` | Bajo |
| **F7 — Telegrafía** | `altura_futura_en_proa(s)` (muestrear donde ESTARÁ la proa) + escalera −12 s → +8 s del artifact. Golpe que quita control: < 0,5 s y recuperarla es acción del jugador | `gobierno.gd`, audio | Cero |
| **F8 — Red** | El último: eje crudo int8 cliente→host (el host corre el MISMO rate-limiter); rueda+pala+muesca+nafta cuantizada host→clientes (ritmo NetAgua); el puesto con el patrón de arbitraje de la bomba (pedir → arbitrar → aplicar, sacar al desconectado); `olvidar_historial_agua()` tras toda corrección dura. **El mar se replica por semilla; el barco por snapshot** (Jolt no es determinista entre máquinas — corrección del artifact a la tesis del CLAUDE.md) | `net/` | Coordinar con RED.md |
| **F9 — La lonja** (diseñada, no bloqueante) | Comprar nafta/bidones con el dinero de DISENO §3; la factura por litros sustituye a la de por distancia. Engancha al inventario en curso de otra sesión | — | Esperar al inventario |

**El primer commit** (F1) no toca nada compartido y deja la matemática
custodiada. **El primer commit perceptible** es F2 (el casco deja de patinar).
Si F2b no cambia nada perceptible, parar y revisar la inercia automática antes
de seguir.

---

## 8 · Las perillas completas (del artifact + nafta)

| Perilla | Arranque | Controla | Si está mal |
|---|---|---|---|
| `inertia.y` | ~95 000 | Peso de la guiñada | Bajo: gira como coche. Alto: no responde |
| `angular_drag` | 1,6 → 0,7 | Amortiguación isótropa | Alto: aplasta el balanceo |
| `area_plano_deriva` | ~9 m² | Resistencia lateral | Baja: hielo. Alta: no vira |
| `pos_plano_deriva.z` | +1,0 a +1,5 | Estabilidad direccional | Delante del CdM: no vuelve al rumbo |
| `area_pala` | ~1,1 m² | Autoridad | Ajustar a 3-5 esloras de círculo |
| `pala_max_deg` | 35° | Tope antes de pérdida | >40°: solo frena |
| `empuje_max` | ~26 000 N | Velocidad punta | Calibrar contra el arrastre existente |
| `motor_rampa_s` | 2,5 s | Inercia longitudinal | Baja: arranca como coche |
| `estela_ms` | 4,5 m/s | Golpe de máquina | Cero: no se maniobra parado |
| `factor_orbital` | 0,6–0,8 | Cuánto roba el mar | 1,0: broaching constante. 0: no existe |
| `vuelta_completa_s` | 5 s | Peso de la rueda | Alto sin animación visible: lag |
| `pala_rate_deg` | **10 °/s** | El servo: la segunda etapa | 2,5 (el de SOLAS, que es de buques de 200 m) dejaba la pala **11 s por detrás** de la rueda: la segunda etapa pasaba a ser el sistema entero |
| `zona_muerta` | 0,10–0,15 | Control fino | 0,5 (el default de Godot): inservible para un eje integrado |
| `tanque_l` | 45 l | Autonomía | Chico: gestión tediosa. Grande: la nafta no existe |
| `consumo_l_min` (toda) | 3,0 | El precio de la prisa | Plano entre muescas: el telégrafo no decide nada |
| `umbral_tos_l` | 6 l | La segunda telegrafía | Cero: el motor muere «sin avisar» (viola regla 8) |
| `bidon_l` | 25 l | El rescate | Mayor que el hueco típico: sobra nafta en cubierta |

## 9 · Diagnóstico rápido

| «Se siente…» | Causa más probable | Dónde |
|---|---|---|
| …que patina sobre hielo | Sin plano de deriva | §3 |
| …que el timón no responde | Falta acuse inmediato (manos/rueda/audio), no sobra inercia | §4, F5 |
| …que gira como un coche | `inertia.y` en automático | §3 |
| …que no vuelve al rumbo | Plano de deriva delante del CdM | §3 |
| …que el barco se hundió sin motivo | El gobierno escribió `constant_force` | §2 |
| …que suena un chapuzón que no pasó | Teleport sin `olvidar_historial_agua()` | F8 |
| …que marea | Rotación heredada del casco sin marco de reposo | F6 |
| …que el golpe suena a cartón | Solo transitorio, falta `trauma_estructural` | F5 |
| …que el mar me robó el barco | Broaching sin telegrafía o sin salida | F7 |
| …que la nafta es un impuesto | Tanque chico o consumo plano: no hay decisión | §5 |

---

## 10 · Lo que este plan NO hace, a propósito

- **Masa añadida traslacional**: investigada y descartada (diverge cerca de
  0,5× la masa; Just Cause 3 y Hydro tampoco la modelan). La inercia
  longitudinal la vende la rampa del motor.
- **Horizon locking / contrarrotación de cámara**: viola la regla 7. El
  inclinómetro de cardán da el beneficio sin tocar un grado de cámara. Si algún
  día entra, es excepción de accesibilidad opt-in.
- **Replicar fuerzas**: no viajan; el host las recalcula de su `Ocean`.
- **Suavizar el input del timón**: 0 ms siempre; lo que se suaviza es la rueda.
- **Reserva automática de nafta**: la reserva es el bidón, y es jugable.

---

## 11 · Lo que F1 dejó cerrado (24-ago-2026)

`tests/gobierno_tests.tscn`, **99 comprobaciones en verde**. Los modelos puros
(`TimonModel`, `MotorModel`) y sus dos balances existen y están custodiados; no
hay ni un nodo todavía, que era el punto: nada de esto choca con la sesión del
hundimiento.

### El signo, resuelto sin barco

La investigación lo dejaba abierto («no lo afirmo de memoria — se comprueba con
el círculo de evolución») y F2 sigue siendo el árbitro final, pero no hacía falta
un barco para cerrarlo: el par de guiñada se calcula con `r × F` y **la banda a
la que cae la proa se deriva de `ω × proa`** en vez de afirmarse en un
comentario. Resultado, ya en verde: *timón a estribor con arrancada avante ⇒ la
proa cae a estribor*.

Lo que el ejercicio destapó es que ahí se cruzan **tres** convenciones de ángulo,
y que ese cruce —y no la fórmula— es donde vive el bug:

1. **El mando** (`-1` babor, `+1` estribor), que es lo que devuelve el InputMap y
   lo único que viaja por el cable.
2. **El ángulo hidrodinámico** (`pala_rad`, `alfa`), positivo hacia estribor
   porque se mide en el mismo sentido que la deriva del flujo — y con la proa en
   −Z eso es una rotación **negativa** sobre +Y.
3. **La rotación visual** del nodo (`rotation.y`), que es la 2 cambiada de signo.

La fórmula del artifact es correcta y se quedó tal cual; el signo vive
**concentrado en una sola línea** (`TimonModel.pala_rad_desde_mando`), con
`yaw_visual()` al lado para que ninguna escena tenga que acordarse. Si F2 lo
desmiente, se invierte ahí y en ningún otro sitio, y el arnés se da la vuelta con
ella.

### Dos números de la investigación que no sobrevivieron a la cuenta

- **`pala_rate_deg` 2,5 → 10 °/s.** Los 2,5 son el mínimo que SOLAS le exige a un
  buque (35° a 35° en 28 s) y este barco mide 12,6 m: con la rueda a 5 s tope a
  tope, la pala habría tardado 14 s en llegar al tope y se habría quedado **once
  segundos por detrás** de la mano. La segunda etapa habría dejado de ser un
  matiz para ser el sistema entero.
- **`tanque_l` 120 → 45 l.** Con 120, la salida tipo gastaba el 15 % del tanque:
  la nafta habría vuelto a ser el número de la factura que DISENO §3 ya tenía. A
  45 l la salida normal usa el 45 %, y quince minutos a avante toda lo vacían —
  el fallo pasa a ser *elegido*, que es lo que la decisión pedía.

### Tres trampas del motor, para la próxima

- **`const` con un empaquetado no se resuelve desde otra clase.**
  `const X := PackedFloat32Array([...])` compila en su archivo pero desde fuera
  el parser lo da por nulo (`Could not resolve external class member`). Va como
  `Array[float]` tipado, igual que `BombaModel.BOMBAS`.
- ⚠️ **Un arnés cuyo script no PARSEA no falla: se cuelga.** Sin script no hay
  `_ready`, así que nadie llama a `get_tree().quit()` y el headless se queda
  girando para siempre — con `--headless` y sin ventana, ni siquiera se ve. Es el
  reverso de la trampa ya conocida («un arnés puede salir verde con un script
  roto: mirar el nº de checks»). **Correr los tests con `timeout`**, o un cuelgue
  se leerá como «tarda un poco».
- **La densidad del agua se LEE de `FloatingBody3D.WATER_DENSITY`**, no se copia.
  El artifact la reescribía con un comentario que decía «la misma que
  FloatingBody3D» — que es exactamente el número en dos sitios que la regla de
  parametrización prohíbe.

---

## 12 · Lo que F2 dejó cerrado, y el muro que encontró (24-ago-2026)

`Gobierno` cuelga del pesquero en `fishing_boat.tscn` y aplica las tres
superficies cada tick. `gobierno_tests` pasa de 99 a **118 comprobaciones**, con
el barco de verdad flotando y virando.

### Lo que ya funciona

- **El círculo de evolución confirma el signo con el casco**, que era el arbitraje
  que la investigación reservaba para esta fase: timón a estribor, la proa cae a
  estribor; timón a babor, cae a babor. Las cuentas de F1 y la física del barco
  dicen lo mismo.
- **Sin arrancada la pala no gira el barco** (menos de 8° en diez segundos), y
  **con un golpe de máquina sí** (más de 10° en el mismo tiempo, arrancando
  parado). O sea: la estela funciona y nadie metió un par directo por el camino.
- **El barco no se hunde con el gobierno empujando**, que es la comprobación por
  consecuencia de la trampa dura: si `Gobierno` hubiera escrito en
  `constant_force`, habría borrado el empuje de la flotabilidad sin un solo error
  en consola.
- La consulta al agua va por **`Ocean.sample()`** y no por `get_submersion()` +
  `get_surface_velocity()` por separado: el propio addon avisa de que pedirlas
  sueltas duplica el coste de lo más caro del sistema, y aquí hacen falta las dos
  en el mismo punto.

### Las medidas, y el error que casi las convierte en una conclusión falsa

⚠️ **Primero, la trampa, porque estuvo a punto de costar una decisión de diseño
equivocada.** El arnés nació midiendo el tiempo con un `1.0 / 60.0` escrito a
mano, y este proyecto corre la física a **120** (`physics_ticks_per_second`). Con
eso, todas las velocidades salían **a la mitad**, y la primera lectura de esta
fase fue que el casco tenía un arrastre monstruoso y que harían falta 310 000 N —
trece veces el motor de un pesquero real— para navegar. Era falso por un factor
de dos. Corregido, la conclusión se da la vuelta: **la velocidad punta está
bien**. El tiempo entra y sale ahora en segundos (`_esperar(segundos)`, leyendo el
ritmo del motor) para que no haya ninguna conversión que equivocar.

El segundo error del mismo día, y de la misma familia: el giro se medía
comparando el rumbo inicial con el final, y `wrapf` no distingue −167° de +193°.
El barco parado con máquina y timón a tope da **más de media vuelta** en diez
segundos, así que el golpe de máquina parecía girar a la banda contraria. Ahora el
rumbo se **acumula tick a tick**.

Las medidas buenas:

| Prueba | Medido | Objetivo | Lectura |
|---|---|---|---|
| Velocidad punta (60 000 N) | **3,94 m/s = 7,7 nudos** | 8-10 nudos | ✅ es velocidad de pesquero |
| Círculo de evolución | **1,2 esloras** | 3-5 | ❌ trompea sobre sí mismo en vez de trazar |
| Parada desde crucero | **8 m = 0,6 esloras** (3,7 s) | 2-4 esloras | ❌ frena corto |
| Overshoot zig-zag 20/20 | 16,9° | — | referencia para comparar tras F2b |

### Lo que sí queda pendiente, y por qué es de F2b

La velocidad ya está; lo que falla es **cómo gira y cómo frena**, y las dos cosas
apuntan al mismo sitio:

- **El círculo de 1,2 esloras es falta de inercia de guiñada.** Es exactamente la
  fila «…que gira como un coche → `inertia.y` en automático» de la tabla de
  diagnóstico del §9. El casco pivota porque nadie le ha dicho todavía que a un
  barco le cuesta girar sobre sí mismo.
- **La parada corta es el arrastre isótropo.** `floating_body.gd` frena con
  `rel_vel.length()`, así que el mismo coeficiente que amortigua el balanceo
  frena el avance.

Las dos palancas son las de F2b (`inertia.y` y `angular_drag`/`drag_coefficient`
en `fishing_boat.tscn`), y **siguen esperando a la sesión del hundimiento** porque
tocan el mismo casco que allí se está calibrando. Los tests afectados no se
relajaron en silencio: **imprimen el número en cada corrida** y llevan el objetivo
escrito al lado, para que la deuda se vea al correr los tests y no duerma aquí.

### Nota para quien haga F2b

El orden importa: **primero `inertia.y`** (cambia el círculo entero), después
bajar el arrastre, volver a medir la velocidad punta con los mismos 60 000 N —y
BAJAR `empuje_max` si se dispara, en vez de dejar el pesquero volando— y solo
entonces afinar `area_pala` contra el círculo. Afinar el área antes es afinarla
dos veces.

---

## 13 · F3: el puesto ya se agarra (24-ago-2026)

El barco **se puede llevar**. `RuedaTimon` cuelga del socket `UpgradeSockets/Helm`,
`PuestoTimonModel` decide y `portador.gd` lo engancha a la mano del jugador.
`gobierno_tests` pasa de 118 a **157 comprobaciones**.

### Las teclas, y por qué ninguna es nueva

| Tecla | En el puesto | Por qué estaba libre |
|---|---|---|
| **A / D** | La rueda | Agarrarla pone `input_captured` en el jugador — el mismo mecanismo con el que la caña ya se queda A/D. La rueda **es** el agarre del timonel (DISENO §2), así que mientras está ahí no anda: no hay conflicto que resolver, hay un rol |
| **W / S** | El telégrafo, una muesca por pulsación | Por lo mismo: con las manos en la rueda, adelante y atrás ya no son pasos |
| **Q** | El contacto | El mismo razonamiento con el que la bomba se quedó la Q |
| **E** | Soltar, y arranca el cabo de trinca | Salir es siempre la misma tecla, como en la bomba |

Las cuatro acciones nuevas van con **deadzone 0,12**, no con el 0,5 que Godot
trae por defecto: un timón integra el eje, y con 0,5 se pierde el control fino
entero.

### La llave: se lleva, no se mete

La decisión de §0 era «sin llave no hay motor», y la primera versión tenía una
ceremonia de meter y sacar la llave del contacto. Se descartó: obligaba a mover
el objeto entre inventarios (y a replicar ese movimiento en F8) sin darle nada al
jugador. **Dar al contacto exige que quien lleva la rueda tenga la llave encima**
—en el cinturón, que es donde vive—; una vez en marcha el motor sigue solo,
porque si hiciera falta la llave para *seguir* andando el timonel no podría
soltar la rueda nunca y el puesto sería una cárcel.

Lo que importaba se conserva entero: la llave **se hunde** (DISENO §2), así que
perderla al agua deja al barco sin poder arrancar y convierte el rescate en una
misión.

### Un fallo silencioso que el puesto destapó

Al montar la rueda, seis pruebas de F2 se pusieron en rojo: el barco había dejado
de virar. La causa era correcta de puro — sin nadie en la rueda, el cabo vence y
el timón vuelve a la vía — pero destapó **un bug de red de verdad**: el guard
estaba puesto sobre «¿llevo yo la rueda?» en vez de sobre «¿la lleva alguien?»,
así que en cuanto un compañero agarrara el timón, **las otras cinco máquinas le
centrarían la rueda**. El timón habría dejado de responder en cooperativo sin un
solo error en consola. Arreglado antes de que existiera la red que lo sufriría, y
con su test.

### Lo que falta del puesto

- **La aguja de nafta y la marca de rey como piezas de arte.** La lógica está
  (`Gobierno.fraccion_tanque()`, `PuestoTimonModel.a_la_via()`) y el aro ya gira
  sus tres vueltas sobre `HelmWheel`; falta el arte en el GLB del barco y su
  generador en `tools/`.
- **El sonido**, que por la regla 10 va por ElevenLabs: arranque, ralentí, la tos
  del tanque bajo, el trinquete de la rueda.
- **Las manos en la rueda** (IK) son de F5, con el resto de la capa de feedback.
