# El menú principal

La primera pantalla del juego: la puerta a los tres modos y a los ajustes, con
el mar de día de fondo.

- Escena: `game/ui/menu/menu_principal.tscn` — y desde ahora es el
  **`run/main_scene`** del proyecto. El juguete de F1 sigue abriéndose directo
  (`--path . game/world/toybox.tscn`) para el ciclo de trabajo de siempre.
- Dentro de la partida: `Esc` abre el menú de sesión y `TAB` la lista de
  tripulación — autoload `Partida` (`game/ui/partida.gd`).
- Arneses: `tests/menu_tests.tscn` (78 comprobaciones) y
  `tests/partida_tests.tscn` (56).
- Capturas para revisar el look: `tests/capture_menu.tscn` y
  `tests/capture_partida.tscn` (necesitan ventana y GPU, no se corren con
  `--headless`).

## El árbol

```
Portada ─┬─ Jugar ────────┬─ Un jugador
         │                └─ Multijugador ─┬─ Hostear una partida
         │                                 └─ Conectarse ── (dirección)
         ├─ Opciones ─── controles + micrófono
         └─ Salir
```

`Conectarse` **no es un tercer modo**: es un paso de multijugador, porque
escribir una dirección no es una decisión distinta de unirse. `Esc` vuelve un
paso, y la miga de pan («Jugar · Multijugador») dice dónde estás.

## El fondo es el mar de verdad

No hay vídeo ni imagen: la escena monta el mismo `OceanSurface3D`, el mismo
`sky.gdshader` y el mismo `DayNightCycle` que la partida. Sale casi gratis —ya
estaba todo escrito— y tiene una consecuencia buena: **si alguien rompe el agua,
el menú se rompe con ella** y se ve al arrancar, no diez minutos después.

Tres decisiones lo sostienen:

1. **La hora está congelada** a las 10:30. `DayNightCycle` tiene ahora
   `hora_congelada`, que deja de sumarle `sim_time` a la fase. La hora sigue
   siendo una función pura (constante es un caso particular de pura), pero un
   fondo que anochece mientras alguien decide si jugar es un reloj corriendo sin
   motivo. Sin esto, quien deja el menú abierto veinte minutos ve una portada
   nocturna que nadie diseñó.
2. **El mar de la portada es más manso, y se devuelve intacto.** La furia baja a
   1,6 (marejadilla) mientras se mira el menú y vuelve a lo que había al abrir
   la partida. No es balance, es FOTO: medido con `capture_menu`, a la furia de
   arranque (3) la nubosidad del cielo se cierra y la pantalla entera se va al
   gris; a 1,6 el horizonte se abre y el agua rompe en rizos, y sigue siendo
   exactamente el mismo mar. La semilla y la lluvia no se tocan. `menu_tests`
   comprueba las dos mitades: que la portada pone la suya y que
   `_devolver_el_mar()` deja la de antes — sin eso, TODAS las partidas
   empezarían con la marejadilla de los botones.
3. **Al empezar a jugar se pone el reloj a cero** (`Ocean.sim_time = 0.0`). Es
   lo único que el menú le escribe al océano, y es justo lo contrario del punto
   anterior: como la hora del día es una función de `sim_time`, sin este reseteo
   quien tarda diez minutos en decidirse empezaría la partida de noche.

La cámara (`CamaraMenu`) hace dos cosas y ninguna más: sube y baja con la ola
que tenga debajo —preguntándoselo a `Ocean`, regla 1— y deriva 0,35 m/s para que
el horizonte no sea una foto fija. **Cero rotación por código** (regla 7): en el
juego esa regla existe contra el mareo; en una portada, además, el horizonte
torcido es lo primero que delata que el fondo es un truco.

## El orden de las operaciones en red

Es la parte donde un menú se rompe de verdad, porque `Net` tiene contratos sobre
la escena que hay cargada:

- **Hostear**: primero se carga el mundo y **después** `Net.hostear()`. El host
  censa `get_tree().current_scene` buscando los props autorados, así que
  hostear desde el menú censaría una pantalla de botones. Antes de nada se
  sondea el puerto abriéndolo y cerrándolo: si ya hay otra instancia hosteando,
  se dice en el menú en vez de dejar al jugador dentro de un mundo en solitario
  creyendo que espera tripulación (regla 8).
- **Conectarse**: al revés. `Net.unirse()` se llama **desde el menú**, y el
  mundo se carga en `connected_to_server`, de forma síncrona. Así hay dónde
  contar que no había nadie escuchando —cargar el mundo antes dejaría al jugador
  en un mar vacío mientras la conexión falla en segundo plano— y el `_hola` del
  host, que llega en un paquete posterior, ya encuentra el barco montado.
- `F9`/`F10` siguen funcionando en el menú, pero los atiende el menú (no `Net`)
  y abren la partida por el camino bueno.

El cambio de escena se hace a mano porque hace falta hacer algo justo después de
que el mundo exista y `change_scene_to_file` es diferido. Y el orden importa:
**primero `root.add_child(mundo)` y después `current_scene = mundo`**, porque el
setter exige que la escena ya cuelgue de la raíz. Al revés falla en voz alta
pero sin detener nada: el mundo aparecía igual y `current_scene` se quedaba
apuntando a la escena vieja —ya liberada—, que es justo por donde censa
`Net.hostear()` y por donde nacen los peces. Lo cazó `menu_tests` al comprobar
que «Un jugador» abre el mundo de verdad.

## El menú de `Esc` y la lista de `TAB` (autoload `Partida`)

La otra mitad: dentro de la partida, `Esc` abre una tarjeta con **Continuar /
Volver al menú / Salir del juego**, y `TAB` (acción `crew`) enseña quién está a
bordo con su retardo. Las dos viven en el autoload `Partida`
(`game/ui/partida.gd`), y son autoload y no un nodo por escena a propósito: así
las tienen todas las escenas jugables sin que nadie se acuerde de instanciarlas,
que es el fallo silencioso clásico.

Tres decisiones:

1. **`Esc` no pausa NADA.** En cooperativo no se puede —el mar de los demás
   sigue— y en solitario tampoco se hace, para que el juego se comporte igual
   solo que acompañado. La tarjeta lo dice en voz alta en vez de fingir: «el mar
   no se detiene».
2. **`Esc` sigue soltando el ratón**, exactamente como antes. La tarjeta se suma
   al gesto que ya existía en `player.gd` (acción `toggle_mouse`), no lo
   sustituye — y por eso es pequeña y centrada: la columna izquierda es del HUD
   de debug del océano, que tiene que seguir alcanzable con el ratón suelto
   (CLAUDE.md: en F1 ese HUD es sagrado).
3. **Volver al menú cierra la sesión primero** (`Net.desconectar()`). Si no, el
   peer se quedaría abierto detrás de la portada y el host seguiría contando con
   un tripulante que ya no está en ninguna escena.

La lista de tripulación y de dónde salen los nombres y los milisegundos está en
`docs/RED.md` §Quién está a bordo. Lo que se ve: el patrón primero, tu fila en
ámbar con «(tú)», y el retardo en verde/ámbar/coral según los umbrales de
`NetTripulacion` — con el número siempre delante, que el color solo acompaña.

## Opciones

**Controles.** La tabla no tiene ni una tecla escrita a mano: cada fila nombra
acciones del InputMap y las teclas se leen de ahí (`ControlesBasicos`). Por dos
motivos: el feedback jamás miente (regla 8) —una lista a mano envejece en
silencio cuando alguien cambia una tecla en `project.godot`— y los teclados no
son todos QWERTY: las acciones de andar están grabadas por código FÍSICO, así
que en un AZERTY hay que enseñar `Z`, y eso lo sabe el sistema operativo. El
arnés comprueba que las diez acciones prometidas existen.

**A bordo.** El nombre con el que sales en la lista de tripulación. Vacío
significa «no he elegido», y entonces manda el que `Net` sacó de la sesión del
sistema operativo — poner «Marinero» de fábrica haría que todos se llamaran
igual hasta que alguien se molestara en escribirlo. Se manda al ENTRAR en una
partida, así que cambiarlo con la partida abierta no reetiqueta a nadie.

**Micrófono.** Lista de aparatos (la primera opción es siempre el del sistema,
la única que se puede prometer), ganancia de 0 a 200 % y **medidor de entrada**:
sin ver la barra saltar al hablar, elegir entre cuatro «Micrófono (Realtek)» es
adivinar. Todo va contra el autoload `Microfono`, que ya sabía hacerlo; el menú
solo lo enseña. Si el aparato elegido se desenchufa, se cae al del sistema y el
menú lo dice.

Los ajustes se guardan en `user://ajustes.cfg` (`MenuAjustes`): un ajuste que no
sobrevive al cierre no es un ajuste. El archivo se relee antes de escribir para
no pisar secciones futuras (vídeo, idioma), y el volumen se acota **al escribir
y al leer**, para que un `.cfg` editado a mano no pueda acabar en la ganancia
del bus. Un archivo roto devuelve los ajustes de fábrica en vez de dejar el menú
sin abrir.

## Tipografía

Todo sale de `GameTypography` (regla 11), y el menú añade una lectura de
`docs/TIPOGRAFIA.md`:

- **Título**: variante ANCHA (`display_brand`) en MAYÚSCULAS. Es el único sitio
  del juego donde manda la voz de marca. El texto sale de
  `application/config/name`, no de una cadena escrita en el código: el nombre
  del juego sigue abierto y no puede quedarse el viejo colgado en la portada.
- **Botones**: la voz de faena (`display_hud`) en **frase normal**, porque los
  menús van en frase normal aunque la fuente sea la de impacto.
- **Todo lo demás** —ayuda, teclas, nombres de aparatos, avisos— en Atkinson,
  frase normal.
- Contorno oscuro y sombra corta en todo, más un velo en degradado por la
  izquierda: el mar pasa de espuma blanca a azul de sombra dentro de la misma
  ola, y el texto tiene que leerse igual.

## Lo que falta

- ⚠️ **Un clic sobre la tarjeta de `Esc` también llega al mundo**: la caña y el
  porteo leen `grab` sondeando `Input` en su `_physics_process`, y eso no pasa
  por el sistema de eventos, así que pulsar «Continuar» lanza la caña de paso.
  No lo trae este menú —pasa desde siempre con el HUD de debug, que es la otra
  pantalla que se usa con el ratón suelto—, pero ahora se ve. El arreglo es una
  guarda de `Input.mouse_mode` en `FishingRod._rod_input_ready()` y en las dos
  lecturas de `Portador`; se deja aparte porque toca una comprobación de
  `porteo_tests` que hoy da por hecho que en headless el clic se escucha.
- **Sonido**: ni un clic. La regla 10 dice que el audio nuevo se genera con
  ElevenLabs, así que el menú se queda mudo hasta que haya sonidos horneados —
  antes que un `SfxLibrary` procedural de más.
- **Lobby de Steam** (RED R2): cuando exista, «Conectarse» dejará de pedir una
  IP y pedirá un amigo. La puerta ya está: `Net.Transporte`.
- Rebinding de teclas, ajustes de vídeo y volumen general.
- El barco en el fondo. Se dejó fuera a propósito: instanciarlo arrastra física,
  inundación y bomba a una pantalla que solo tiene que verse bien.
