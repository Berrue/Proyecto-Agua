# La red — la costura jugador↔barco↔mar, cerrada

Estado: **R0 funcionando en localhost** (2026-08-23). Código:
`game/net/network_manager.gd` (autoload `Net`) + `game/net/net_math.gd` (la
matemática pura de la costura). Tests: `tests/net_tests.tscn`. Este documento
cierra el hallazgo nº3 de la review del plan ("costura sin diseñar — diseñar
ANTES de escribir red") y le da a F1 su red mínima (hallazgo nº4).

## Por qué la red de este juego es barata

El océano es función pura de `(posición, tiempo, semilla, furia)`. No se
replica el agua: se replican **~50 bytes de estado** (semilla al unirse; reloj
y furia en goteo; cada evento —tsunami, ola rebelde— un solo RPC fiable con
sus parámetros) y cada máquina evalúa EXACTAMENTE el mismo mar. El preset
gráfico no importa, el frameskip no importa: la fórmula es la misma.

## Los tres contratos (la costura)

Son los tres fallos que la review predijo, y su solución es UNA decisión cada
uno. Se escriben acá para que nadie los "optimice" de vuelta:

1. **Los jugadores se replican en espacio LOCAL del barco** (`transform`
   relativo al casco), jamás en espacio mundo. Cada máquina los compone
   contra SU copia del barco (`NetMath.a_mundo(barco_local, T_local)`). Sin
   esto, con mar gruesa todos flotan despegados de la cubierta en las
   pantallas ajenas, porque cada barco replicado vive en un instante
   distinto. La simulación local sigue siendo world-space (move_and_slide
   sobre la cubierta); lo local-al-barco es SOLO el cable.
2. **El cliente evalúa el océano en el reloj RETRASADO de la interpolación.**
   El barco llega del host con ~100-150 ms de buffer; si el agua local se
   evaluara en "ahora", con Hs 6 m habría hasta medio metro de aire entre el
   casco replicado y la ola local. El reloj del cliente persigue
   `t_host − RETARDO_INTERP` con una corrección LENTA (slew acotado, nunca
   saltos): el shader, la física local y las consultas usan ese único
   `Ocean.sim_time`, así que barco, agua y espuma coinciden por construcción.
   Es gratis porque el agua es función pura de t.
3. **Autoridad en cuatro niveles, sin predicción ni rollback** (coop de
   amigos, no competitivo): tu jugador es TUYO (cliente-autoritativo); el
   barco, la carga y los props son del HOST (los clientes congelan su física
   e interpolan — el barco congelado queda en freeze KINEMÁTICO, que reporta
   velocidad real a los contactos y por eso la cubierta sigue "llevando" a
   los personajes); al AGARRAR un objeto la autoridad pasa a ese cliente y
   vuelve al soltarlo (el porteo ya declara su estado mínimo: dos ids y un
   enum — fase C de PORTEO.md); daño, muerte y estado del mar son del host y
   fiables.

## Qué viaja por el cable (R0)

| Mensaje | Modo | Cadencia | Contenido |
|---|---|---|---|
| `hola` (host→nuevo) | fiable | 1 vez al unirse | semilla, sim_time, furia, lluvia |
| `estado_mar` | no fiable ordenado | 10 Hz | sim_time, furia, lluvia |
| `estado_barco` | no fiable ordenado | 20 Hz | stamp (sim_time del host), posición, cuaternión |
| `estado_jugador` | no fiable ordenado | 20 Hz | peer, posición LOCAL al barco, yaw, y 3 números de animación (ratio, agua, lucha) |

Los clientes mandan su `estado_jugador` al host y el host lo reparte (relay):
2-6 amigos, el ancho de banda da igual; la topología simple gana. La sombra y
la copia que ven los demás se animan con los MISMOS tres parámetros que ya
alimentan al animator local — el árbol se montó para esto (ANIMACION.md).

## Qué añade R1

| Mensaje | Modo | Cadencia | Contenido |
|---|---|---|---|
| `estado_cuerpos` | no fiable ordenado | 20 Hz | **un solo paquete** con todos los cuerpos sueltos: `[t]` + 23 B por cuerpo (id, flags, pos f32, rot f16) |
| `pedir_porteo` (cliente→host) | fiable | por gesto | id del cuerpo, verbo, índice de socket, velocidad |
| `aplicar_porteo` (host→todos) | fiable | por gesto | lo mismo + quién y el transform de destino |
| `porteo_denegado` (host→uno) | fiable | por rechazo | motivo y quién ganó |
| `pedir_pez` / `nacer_pez` / `muere_pez` | fiable | por pez | índice de especie, posición, velocidad, giro |
| `evento_tsunami` | fiable | por evento | objetivo, dirección, segundos, tier y **`t0` del host** |
| `limpiar_eventos`, `estado_dia`, `pedir_debug` | fiable | por acción | los mandos del HUD de debug reenviados al host |
| `pedir_bomba` (cliente→host) | fiable | por gesto | índice de estación (`BombaModel.BOMBAS`, APPEND-ONLY) y verbo |
| `aplicar_bomba` (host→todos) | fiable | por gesto | lo mismo + quién. La palanca manda FLANCOS, no muestreo |
| `bomba_denegada` (host→uno) | fiable | por rechazo | el motivo, para poder decírselo |

Y el `hola` crece: además de la semilla lleva **los eventos en vuelo** (quien se
une a mitad de tsunami ve la ola, no un mar plano) y **el censo entero** (quién
lleva qué en la mano).

**Las tres decisiones que R1 cierra:**

0. **Por qué los props no se simulan en cada máquina**, aunque el océano sea
   determinista: el cliente evalúa el mar en el reloj **retrasado** de la
   interpolación (contrato 2), y eso no es un defecto, es donde vive su barco.
   Medido: a furia 3 el agua difiere hasta **18 cm** entre los dos relojes, y
   a furia 6 hasta **42 cm** — el «medio metro de error vertical» que la
   review del plan predijo, ahora con número. Un prop simulado en local
   flotaría sobre otra agua. `net_tests` lo mide en cada corrida.
1. **Identidad por lista literal.** Los cinco props autorados son hijos
   directos de la raíz con el mismo nombre en las dos escenas, así que su id
   es su índice en `NetPorteo.CUERPOS_ESCENA` — las dos máquinas lo leen de
   disco y no hay nada que negociar. Los que nacen en partida (peces) los
   numera el host desde `ID_DINAMICO_BASE`. El día que el mundo deje de ser
   una escena autorada, esto necesita una spawn table de verdad.
2. **Agarre PESIMISTA.** El cliente pide y espera; el prompt dice
   «pidiendo…», que es honesto. Un agarre optimista revocado por el host es
   literalmente «me robó» — el objeto aparece en tu mano y desaparece 120 ms
   después, sin forma de avisar antes, y la regla 8 lo prohíbe con esas
   palabras. Con 80-150 ms se lee como estirar el brazo. **El host agarra al
   instante**: es la autoridad, y la asimetría es la misma que ya pagan los
   clientes por el barco y por el mar. Bonus: el camino pesimista tiene
   *menos* código, porque no existe el rollback.
3. **Marco local por cuerpo, no reparentando.** Cada cuerpo lleva un bit que
   dice si su transform va en espacio del barco (contrato 1) o en mundo. Eso
   compra el contrato sin mover los props bajo `FishingBoat` en las escenas,
   que es el cambio con más riesgo de conflicto del proyecto.

**El invariante que más caro sale de olvidar:** un cuerpo que entra en una
mano, un gancho o un cinturón **deja de moverse por snapshots** — su sitio lo
dice el socket del que cuelga. Si no se limpian sus buffers de interpolación,
el cliente sigue reescribiéndole el transform cada tick y el objeto se queda
soldado a la cubierta mientras su dueño camina con la mano vacía. Y no hace
falta ninguna carrera de paquetes para verlo: al agarrar, el buffer ya tiene
hasta ocho snapshots legítimos, el host deja de mandar más (los no-sueltos no
entran en el lote) y el muestreo *clampa* al último en vez de apagarse.

**Y una regla de doctrina que este diseño destapó, y que vale para todo el
repo:** *una escritura de transform ES un teleport, y un teleport fabrica un
slam.* `FloatingBody3D` calculaba la velocidad de entrada al agua contra una
profundidad anterior que no se reseteaba nunca, así que mover un cuerpo a mano
disparaba un chapuzón con SFX y espuma que no había ocurrido. Era un bug
presente **sin red** (soltar un farol bajo el agua ya lo producía) y la red lo
habría multiplicado por cada cuerpo y cada devolución de autoridad. Se arregla
con `olvidar_historial_agua()`, y hay un test que lo vigila.

## Qué NO hace R0 (y dónde queda)

- **Props y peces**: siguen siendo física local en cada máquina (divergen).
  R1 los congela en clientes e interpola del host, con el spawn del pez
  pedido al host. La bodega no necesita red propia: cuenta por presencia
  física, así que con los props replicados la cuota coincide sola.
- **Porteo en red** (fase C de PORTEO.md): tomar/soltar/colgar como RPCs con
  transferencia de autoridad. Los verbos ya existen y el estado replicable ya
  es mínimo; R1 los cablea.
- **Eventos del océano**: el tsunami se replica como la LLAMADA
  (`spawn_tsunami_tier(target, dir, seconds, tier)` + sim_time de lanzamiento),
  un RPC fiable — cada cliente evalúa la onda localmente. R1.
- **El HUD de debug en cliente**: no está bloqueado; si el cliente mueve la
  furia, el siguiente `estado_mar` (≤100 ms) la pisa. El dios del slider es
  el host, como pide el juguete F1.
- **Steam (SDR) y voz por proximidad**: R2, al final, como dice el plan. ⚠️ Y
  **no es "una línea"**, aunque este doc lo dijera: el cambio de peer sí son
  cuatro (`_crear_peer_host`/`_crear_peer_cliente`, ya detrás de la puerta
  `Net.Transporte`), pero `unirse(destino)` deja de aceptar una IP y pasa a
  hablar de Steam IDs y lobbies, `MAX_JUGADORES` deja de aplicarlo el transporte
  y se muda al lobby, y hacen falta inicialización de Steam, callbacks,
  invitación por overlay y reconexión. Medido contra el código: 2-4 días el
  transporte y 1-2 semanas más el lobby y su UI.

## Cómo se prueba (F1, dos ventanas)

1. Instancia A: `F9` (o `--net-host`) — se vuelve host en el puerto 4247.
2. Instancia B: `F10` (o `--net-join=127.0.0.1`) — se une, recibe la semilla,
   regenera SU océano y aparece en la cubierta del host.
3. La validación que importa (PLAN, verificación): no comparar posiciones
   lado a lado — comprobar que **el barco replicado se asienta sobre el agua
   que ESE cliente evalúa localmente**, sin hueco ni clipping. Esa es la
   costura entera en una mirada.

## Fases

- **R0 — El mismo mar y vernos (HECHA).** ENet localhost detrás de `Net`;
  semilla+reloj+furia+lluvia replicados con reloj retrasado; barco
  host-autoritativo congelado-kinemático e interpolado; jugadores en espacio
  local del barco con cuerpo visible y animación replicada; overlay mínimo
  de estado. `NetMath` es pura y testeable (composición local↔mundo, slew
  del reloj, interpolación de snapshots) y `net_tests` incluye un loopback
  ENet real en un solo proceso.
- **R1 — Las cosas en las mismas manos (HECHA).** Props y peces
  host-autoritativos (congelados-kinemáticos en el cliente, **con la capa de
  colisión intacta**: si se les quitara, la bodega del cliente marcaría cero
  mientras la del host marca sesenta kilos); censo con identidad estable;
  porteo completo con transferencia de autoridad y arbitraje en el host
  (PORTEO fase C); el pez lo pare el host pero la **especie la decide quien
  pescó** —lleva treinta segundos viéndola en el HUD, re-sortearla sería
  feedback que mintió—; eventos del océano con `t0` explícito; el HUD de
  debug reenvía sus mandos al host en vez de mutar su copia; y latencia
  simulada propia (`NetLag`, `--net-lag=120,30,2`), porque la promesa de
  «netfox trae el toggle» no tenía una línea de código detrás.

  El estado estable cuesta **cero bytes por segundo**: un cuerpo que se queda
  quieto manda un último snapshot con el bit DORMIDO y el cliente lo compone
  contra el barco a partir de ahí. Ningún cuerpo duerme solo (`FloatingBody3D`
  fuerza `can_sleep = false`), así que se mide a mano con histéresis.
- **R2 — Steam y voz.** GodotSteam (SDR) como transporte, two-voip, atenuación
  por furia (la mejor idea de diseño del proyecto). Al final, como manda el plan.
  **ENet NO se sustituye: se queda como transporte de desarrollo y de tests.**
  Steam es una sesión por PC —el peer identifica por Steam ID, no por IP—, así
  que con Steam se acaba el ciclo de dos ventanas en la misma máquina, que es el
  ciclo con el que se depura todo lo demás, y `net_tests` se quedaría sin su
  loopback. Por eso `Net.Transporte` tiene las dos ramas y ENET es el defecto;
  `--net-transporte=steam` elige la otra.
