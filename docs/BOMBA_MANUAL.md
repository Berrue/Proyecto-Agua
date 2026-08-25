# Bomba manual de achique — contrato del módulo

## Papel en el juego

La bomba manual es una estación cooperativa, no una mejora automática ni un
botón. `DISENO.md` fija su dinámica: una persona acciona una palanca de dos
posiciones y otra lleva la aspiración hasta la celda que contiene agua. Una sola
persona podrá achicar con rendimiento reducido; dos personas coordinadas
alcanzarán el caudal completo.

Esta primera entrega protege solamente el objeto, su escala y el verbo de
**coger, desplegar y soltar la manguera**. Todavía no extrae agua, no consulta
celdas inundadas, no calcula presión, no cavita y no ocupa al operador de la
palanca. La pesa de cadencia y la palanca existen como piezas separadas para que esas
mecánicas puedan entrar después sin rehacer el asset.

## Alcance de esta fase

Incluye:

- bomba tardomedieval de tronco ahuecado, palanca, vástago y base de vigas;
- testigo vertical con pesa y tres muescas, sin reloj circular moderno;
- espiga de aspiración y canaleta fija de descarga de madera;
- manguera de cuero embreado, reserva enrollada y tramo desplegable;
- cesta-colador de sauce lastrada, con zona de agarre;
- agarre y suelta mediante una API que no conoce a `Player`;
- seguimiento de un `Marker3D` externo y límite explícito de longitud;
- escena completamente independiente y una escena de pruebas headless.

Queda fuera:

- retirar agua o cambiar el estado de una celda;
- decidir en qué celda está el cabezal;
- el ritmo de mantener/soltar, presión, caudal y cavitación;
- audio, vibración, animación final y HUD;
- autoridad multijugador;
- ~~extraer agua de verdad~~ — **hecho** el 24-ago-2026, ver «Integración de
  achique» más abajo. Lo que sigue fuera es el FEEL: ritmo de mantener/soltar,
  cavitación, la pesa animada y el audio.

## Base histórica y licencias

La dirección visual parte de la bomba hallada en el [barco medieval de Newport](https://www.newportship.org/artifacts),
un mercante de mediados del siglo XV. El archivo arqueológico conserva tubo y
base de madera, lanza de bombeo, válvulas de cuero, clavos, cuerda, fragmentos de
cestería y una caja protectora. El [informe de cuero de Newport](https://archaeologydataservice.ac.uk/catalogue/adsdata/arch-1563-2/dissemination/pdf/Newport_Medieval_Ship_Specialist_Report_Leather.pdf)
identifica cuero bovino y correas de la válvula. Es la familia material del
asset: olmo, fresno, hierro forjado, cuero, cáñamo, brea y sauce.

Hay dos licencias jugables explícitas:

1. La aspiración medieval documentada era fija en la sentina. La manguera móvil
   se conserva porque elegir y alcanzar una celda es parte central de `DISENO.md`.
   Se expresa como cuero cosido y reforzado, nunca como goma industrial.
2. El indicador vertical de cadencia es una invención verosímil. Sustituye al
   manómetro circular —tecnología muy posterior— usando solo pesa, guía, muescas
   y topes capaces de traquetear.

## Escala y lectura visual

La pieza tiene que leerse como algo construido por el carpintero y el herrero
del barco, no como maquinaria contemporánea revestida de madera:

- huella de montaje máxima: **0,80 m de ancho × 1,20 m de fondo**;
- base aproximada: 0,45 × 0,35 m;
- cuerpo: 0,90–1,00 m desde la cubierta;
- palanca: aproximadamente 0,65 m, con pivote reconocible;
- manguera: 0,055 m de diámetro exterior;
- cabezal/colador: 0,25–0,30 m, con empuñadura visible;
- longitud máxima desplegada inicial: 6,5–7,0 m.

Materiales: tronco de olmo facetado por azuela, palanca de fresno, soleras de
roble, abrazaderas de hierro ennegrecido, empaquetaduras de cuero, ligaduras de
cáñamo y cesta de sauce. La palanca, el testigo tallado y la cesta tienen que
distinguirse a varios metros; son las tres invitaciones a interactuar.

La manguera se **desenrolla y se endereza**. No se escala como goma elástica.
Al alcanzar su longitud máxima queda tensa: el cabezal puede limitarse al radio
disponible o soltarse con aviso en una fase posterior, pero la geometría nunca
puede superar silenciosamente el máximo.

## Encaje futuro en el barco

La escena esperada es:

`res://game/boat/equipment/manual_bilge_pump.tscn`

**Ya está montada** (petición del usuario, esta pasada). Su raíz cuelga
directamente de:

`FishingBoat/UpgradeSockets/PumpPort`

El socket existente está en `Vector3(-1.3, 1.05, 0.75)`, **25 cm sobre la
cubierta**, y su eje local `-Z` mira hacia el pasillo central. Por eso:

- la raíz del módulo representa el origen del socket;
- `MountOrigin` queda en `(0, 0, 0)`;
- `BaseContact` queda en `(0, -0.25, 0)`;
- la cara funcional y `OperatorStand` quedan hacia `-Z` local;
- la base visual toca `Y local = -0.25` al montar;
- la bobina y los racores pueden ocupar el lado exterior `+Z` local.

La convención se cumplió: la instancia entra **sin un solo offset**
(`position` y `basis` en identidad) y sin tocar el GLB del barco. `PumpStarboard`
sigue reservado para la segunda bomba/mejora.

Dos consecuencias del montaje que conviene tener presentes:

1. **Lo que frena al jugador no vive en la bomba.** Como el resto del mobiliario de
   cubierta (`soporte_cania`, `gancho_farol`), el módulo es arte + `Area3D`. El
   cuerpo sólido es `PumpPortShape`, una caja nativa en la raíz del barco, igual
   que `HelmConsoleShape` para la consola del timón: en este barco el GLB nunca
   importa física. Está medida del AABB real de `PumpVisual` y queda por dentro del
   arte, para que no aparezca una pared invisible junto a la borda.
2. **`PumpVisual/IntakeHead` se mueve en runtime** — `stretch_hose` la lleva
   siguiendo a la manguera. Cualquier medida automática del módulo tiene que
   excluirla o será intermitente; `boat_asset_tests.gd` lo hace explícitamente.

`tests/manual_pump_tests.tscn` dejó de comprobar que la bomba NO estuviera montada
y ahora comprueba lo contrario: que está instanciada **desde su propia escena**,
que cuelga de `PumpPort` sin offsets y que `BaseContact` aterriza exactamente en la
cubierta (Y 0,80).

## Estructura de nodos

Los nombres siguientes son parte del contrato testeable. Pueden existir nodos
intermedios adicionales para arte o simulación, pero estos deben poder hallarse
recursivamente:

```text
ManualBilgePump (Node3D, script del módulo)
├─ MountOrigin (Marker3D, posición cero)
├─ BaseContact (Marker3D, y = -0.25)
├─ PumpVisual (GLB editable: madera, hierro, cuero, mimbre)
│  ├─ PumpBase / PumpBody / IronHoops (MeshInstance3D)
│  ├─ LeverArm / PumpSpear / LeverGrip (MeshInstance3D)
│  ├─ CadenceRack / CadenceTongue (MeshInstance3D)
│  └─ HoseCoil / IntakeHead / DischargeDale (MeshInstance3D)
├─ PumpBase (Node3D de referencia para montaje)
├─ LeverPivot (Node3D)
│  └─ Lever (Node3D de referencia para animación)
├─ CadenceIndicator (Node3D)
│  └─ CadenceWeightPivot (Node3D de referencia para animación)
├─ HoseAssembly (Node3D)
│  ├─ Anchor (Marker3D)
│  ├─ HoseRest (Marker3D)
│  ├─ StoredCoil (Node3D de referencia a PumpVisual/HoseCoil)
│  ├─ HoseMesh (MeshInstance3D, malla dinámica)
│  └─ PickupHead (Area3D con CollisionShape3D; mueve PumpVisual/IntakeHead)
├─ OperatorStand (Marker3D, hacia -Z)
└─ PlacementFootprint (Marker3D o Node3D de guía)
```

`LeverPivot` y `CadenceWeightPivot` son referencias nativas alineadas con los
orígenes editables de `PumpVisual/LeverArm` y `PumpVisual/CadenceTongue`. Todavía
no conducen esas mallas: la mecánica futura deberá enlazarlas explícitamente con
un `AnimationPlayer` o desde el script de bombeo. `Anchor` nunca se mueve;
`PickupHead` es el extremo que sigue al agarre y a la vez su `Area3D`
interactuable. Debe conservar una capa detectable cuando la manguera está
apoyada y dejar de bloquear físicamente al jugador mientras está en mano.

## Contrato de agarre

La bomba no recibe un `Player`, no lee inputs y no modifica `hands_busy`. Recibe
un nodo de agarre cualquiera. La capa del jugador decidirá después si ese agarre
pertenece a una mano, una cámara, IA o una prueba.

API pública requerida en la raíz:

```gdscript
func tomar_manguera(grip: Node3D) -> bool
func soltar_manguera() -> void
func esta_manguera_tomada() -> bool
func posicion_toma_global() -> Vector3
func get_hose() -> Node
func get_mount_footprint() -> Vector2
func get_mount_plane_y() -> float
```

API pública requerida en `HoseAssembly`:

```gdscript
func tomar(agarre: Node3D) -> bool
func soltar() -> void
func esta_tomada() -> bool
func get_tip_global_position() -> Vector3
func get_deployed_length() -> float
func get_max_length() -> float
func set_deployed_length(nueva_longitud: float) -> void
func reset_hose() -> void
```

Señales de la raíz y de `HoseAssembly`:

```gdscript
signal hose_taken(grip: Node3D)
signal hose_released()
signal tomada(agarre: Node3D)
signal soltada()
signal tension_changed(tension: float)
signal max_length_reached()
```

Reglas:

1. `tomar_manguera()`/`tomar()` fallan si ya está en otra mano o el agarre es
   inválido.
2. Por debajo del máximo, el cabezal sigue el agarre sin retraso perceptible.
3. La forma intermedia puede tener inercia; el extremo agarrado no.
4. `get_deployed_length()` siempre devuelve un número finito entre cero y
   `get_max_length()`, incluso si el agarre salta o la raíz rota bruscamente.
5. `soltar_manguera()` reactiva su zona de interacción y conserva una velocidad
   inicial si la implementación la usa.
6. Llevar la manguera será una tarea de **una mano**. La integración futura no
   debe usar el `hands_busy` actual, que representa dos manos ocupadas.

En el proyecto `grab` (clic izquierdo) pertenece a la caña. La toma/suelta se
integrará con `interact` (E), pero el módulo no debe escuchar esa acción. Un
único interactor del jugador hará el raycast y llamará esta API para evitar que
farol, manguera y herramientas futuras compitan por el mismo evento.

## Simulación visual recomendada

La manguera debe simularse en el espacio local del módulo con puntos
PBD/Verlet, el primer punto fijado a `Anchor` y el último a `PickupHead` o al
agarre. La gravedad se transforma al espacio local y una malla tubular de pocos
lados se reconstruye sobre los puntos.

Esto evita una cadena de cuerpos rígidos y joints que, al montar la estación,
podría transferir impulsos espurios al único `RigidBody3D` del barco. También
evita replicar decenas de transforms: en multijugador bastará sincronizar quién
sostiene el extremo, su posición local y el estado funcional de la bomba; cada
cliente reconstruirá la curva como presentación.

Las colisiones completas de cada tramo no forman parte de esta fase. El cabezal
`PickupHead` sí necesita una `CollisionShape3D`. Más adelante se pueden añadir
restricciones baratas contra cubierta/mamparos sin cambiar la API.

## Controles previstos

- **E / interactuar:** coger o soltar el cabezal, mediado por el futuro
  interactor central del jugador.
- **Clic izquierdo / grab:** reservado para accionar la palanca cuando el
  jugador esté ocupando la estación; no se implementa todavía.
- **Mantener/soltar:** el diseño futuro leerá el ritmo mediante la pesa y sus
  tres muescas talladas; el tope superior traquetea al cavitar.
- **Movimiento:** quien dirige la manguera conserva el movimiento; quien bombea
  podrá quedar comprometido con la estación durante cada carrera de la palanca.

## Integración de achique (hecha, 2026-08-24)

**La bomba ya achica.** Mientras alguien la acciona, le saca agua a la celda que
contiene el cabezal — `posicion_toma_global()` → `FloatingBody3D.probe_index_at()`
→ `drain_probe()` —, y el módulo sigue sin conocer los nombres de las celdas.

- **Estación**: `EstacionBombeo` (Area3D propia, porque el cuerpo sólido
  `PumpPortShape` vive en la raíz del RigidBody del barco y un raycast contra él
  devuelve el `FishingBoat` entero). `ocupar_estacion` / `liberar_estacion` /
  `set_bombeando`, con `ocupante` y `portador_manguera` como peer id.
- **Controles**: `E` sobre el cuerpo ocupa la estación (las **dos** manos), `E`
  sobre el cabezal lo lleva (**una** mano, conservas el movimiento), mantener
  **clic** bombea, `E` o dar un paso sale. Todo pasa por el interactor único
  (`Portador._interactuar_bomba`); el módulo no escucha input, como manda este doc.
- **50 % / 100 % sin candado**: el caudal es pleno con el cabezal sostenido por
  alguien y la mitad con el colador tirado en cubierta. La interdependencia sale
  de la cuenta de manos — el que bombea no tiene manos para dirigir la manguera —,
  no de un rol. El solitario puede hacerlo todo: soltar el cabezal dentro de la
  celda anegada, volver a la palanca y achicar al 50 %.
- **Balance**: `caudal_bomba` vive en `resources/agua/agua_embarcada.tres`, junto
  a las entradas de agua. Entrada y salida son los dos lados de la misma balanza
  y el punto de equilibrio ES el dial de dificultad: separarlos en dos recursos
  permitiría afinar uno sin ver el otro.
- ⚠️ **«Elegir qué celda achicar» ya NO es la decisión** (24-ago-2026). El agua
  dejó de inclinar el barco y las celdas dejaron de ser visibles para el jugador:
  ahora hay UN nivel de agua y el barco se hunde recto. Lo que decide el
  achicador es el ritmo —llenar, cambiar el selector, sacar la manguera por la
  borda— y mantener el colador dentro del agua. Ver `docs/DECISIONES.md`.
- **Autoridad**: el caudal y las celdas son del host (`_physics_process` sale de
  inmediato en un cliente). El arbitraje vive en `BombaModel`, puro y testeable.
- **En red (24-ago-2026): la estación ya viaja.** Los seis verbos —ocupar,
  liberar, accionar on/off, tomar y soltar el cabezal— van por el patrón del
  porteo: `Net.pedir_bomba()` → el host arbitra con `BombaModel.arbitrar` → lo
  difunde con `_aplicar_bomba`, y el que pierde la carrera recibe su motivo por
  su nombre. **Agarre pesimista**: el cliente no toca nada hasta que el host
  contesta, porque una palanca que se te concede y se te revoca 120 ms después
  es el «me robó» que prohíbe la regla 8. La palanca manda **flancos**, no
  muestreo: son dos eventos por segundo como mucho, no sesenta RPC. Y si alguien
  se desconecta, el host lo saca de la estación (`_liberar_bombas_de`) — una
  bomba ocupada por quien ya no está es un barco que nadie puede achicar.
  La identidad de las estaciones es `BombaModel.BOMBAS`, **APPEND-ONLY** por
  índice: la segunda bomba entra al final o dos versiones del juego dejan de
  entenderse en silencio.
- **Lo que la revisión del cableado obligó a arreglar** (y que ningún arnés podía
  ver, porque los RPC no se testean): el host arbitraba `MANOS_LLENAS` con una
  cuenta que **no veía las estaciones**, así que para él alguien con las dos manos
  en la palanca tenía cero manos ocupadas — podía además llevar el colador y sacar
  cosas del cinturón mientras bombeaba, cosa que el solitario sí denegaba. Falta
  un candado de «petición en vuelo» como el del porteo: dos E dentro de la misma
  ida y vuelta mandaban dos verbos distintos y el host aceptaba los dos (**tres
  manos**); el candado cubre solo los verbos de agarre, nunca la palanca, porque
  sus flancos no se reintentan y descartar un `ACCION_OFF` dejaría la bomba
  accionada. `_liberar_manos()` ponía las manos a cero **a ciegas**, así que salir
  de la estación con el colador en la mano desbloqueaba el salto y la caña: ahora
  recuenta. Y al **caerse el host**, la estación quedaba a nombre de un peer que ya
  no existe y `arbitrar` contestaba OCUPADA para el resto de la partida — nadie
  podía volver a achicar.
- **Lo que NO viaja**: `carga_camara`. Es host-only, así que el nivel de un
  invitado puede ir hasta un 3 % por debajo del real. No se ve en nada (esa agua
  no le quita empuje a ninguna celda en ninguna máquina) y la alarma y el
  naufragio viajan como banderas ya decididas por el host. Lo que **sí** viaja es
  el aviso de **cámara llena**, un bit por estación en el byte de banderas que ya
  mandaba `NetAgua`: sin él, un invitado en la palanca vería la bomba dejar de
  mover agua sin que nada cambiara en pantalla — la única forma de fallar de la
  mecánica que no se ve sola.

**La bomba tiene dos modos, y el selector vive en la propia bomba.** Lo mueve
quien está en la palanca (tecla Q mientras ocupas la estación), no quien lleva la
manguera.

- **SUCCIÓN**: mientras alguien acciona la palanca, el depósito se llena desde la
  celda donde esté el colador. Va **al doble de rápido si otro sujeta el colador**
  y lo apunta al agua; suelto en cubierta se tumba con el cabeceo y traga aire.
- **EXTRACCIÓN**: el agua sale sola por la manguera, como una manga de bombero.
  No hace falta bombear, así que **esto lo hace una persona sola**: coge el
  colador, lo saca por la borda y lo suelta todo.

Y **a dónde va el agua lo decide dónde apuntas**. Punta fuera del casco (se mide
en planta contra el `HullShape` real): al mar, y esa es la única puerta por la que
el agua abandona el barco. Punta dentro: cae en la celda de debajo y no has
arreglado nada — solo has movido el problema y mojado a quien pasara. Dejarse el
selector en EXTRACCIÓN con la manguera recogida vacía el depósito de vuelta en
cubierta. No está prohibido a propósito: es el fallo que se ve.

El depósito se mide en **segundos de bombeo** (8 por defecto) y no en litros, y no
es pereza: para que esta bomba aguante una tormenta tendría que mover unos 480
litros por segundo — un camión de bomberos, no una bomba de palanca. Un número de
litros realista sería mentira. Lo que sí es real es cada cuánto hay que parar,
cambiar el selector e irse a la borda; y mientras uno vacía, está expuesto.

El agua del depósito **sigue contando como agua a bordo** hasta que sale. Llenar
no salva el barco: solo mueve el agua de sitio y lo endereza. Salvarlo es apuntar
afuera.

Queda pendiente la capa de FEEL que este doc describe más arriba: carrera y
cadencia de `LeverPivot`, la presión representada en `CadenceWeightPivot`, el
cabeceo desplazando el ritmo, la cavitación y su penalización, y el audio. Hoy la
palanca no se anima; la señal `embolada(con_agua)`, con el periodo de la carrera
de esta bomba, está lista para colgar de ella el sonido y el chorro. Y con el
ciclo tal como está, machacar el clic rinde lo mismo que un vaivén tranquilo: es
la banda de cadencia la que tiene que hacer óptimo UN ritmo, no solo castigar
mantener apretado.

## Checklist de entrega

- [x] La escena carga e instancia sin `Player`, barco ni océano.
- [x] Está instanciada en `fishing_boat.tscn` bajo `UpgradeSockets/PumpPort`,
  sin offsets, con `PumpPortShape` como cuerpo sólido en la raíz del barco.
- [x] Su raíz se puede alinear directamente con `PumpPort`.
- [x] `MountOrigin` está en cero y `BaseContact.y` vale -0,25 m.
- [x] La huella declarada no supera 0,80 × 1,20 m.
- [x] Palanca, pesa, bobina y cesta-colador son piezas separadas/editables.
- [x] `PickupHead` es un `Area3D` detectable con una colisión simple.
- [x] La API de agarre no referencia la clase `Player`.
- [x] El extremo sigue un agarre mientras se traslada y la raíz rota.
- [x] Mover/rotar la raíz completa no deja la manguera en el mundo.
- [x] La longitud nunca supera el máximo ni produce NaN/INF.
- [x] Soltar vuelve a dejar el cabezal disponible.
- [x] ~~Todavía no modifica agua, celdas, presión ni caudal.~~ Ya achica: modifica
  la celda del cabezal (nunca las demás). Presión y cadencia siguen pendientes.
- [x] Existe captura standalone retraída y desplegada, con referencia humana.
- [x] `tests/manual_pump_tests.tscn` pasa con Godot 4.7.2.
