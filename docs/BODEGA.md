# Bodega de pescado

`game/boat/bodega.tscn` es la pieza editable de la bodega: piso y paredes de
roble, listones, tapa, clavos, bisagras de hierro forjado y el pizarrón viven en
la escena. `bodega.gd` conserva solamente el conteo dinámico y la actualización
de la escritura de tiza.

## Montaje

- El origen coincide con el anclaje de cubierta.
- En la escena suelta, `-Z` apunta a proa y el pizarrón mira hacia `+Z` (popa).
- Está instanciada en `FishingBoat/UpgradeSockets/HoldAft/Bodega` **rotada 180°**:
  montada en el barco, el pizarrón se lee **desde proa** y la tapa abre hacia popa.
- Es `AnimatableBody3D` para acompañar al casco sin perder el comportamiento
  físico de los peces, pero con **`sync_to_physics = false`**. Con el valor por
  defecto el nodo se reescribe cada paso con la pose que le devuelve el servidor
  de física; esa pose va un paso por detrás del casco, que en ese mismo paso ya se
  movió, y el desfase se cobra sobre la posición LOCAL: la celda se despegaba del
  socket 30 cm y 1° en el primer segundo de mar gruesa, y no volvía. Colgando de un
  `RigidBody3D` la única verdad válida es el árbol de escena. El cuerpo cinemático
  sigue reportando su movimiento al solver igual que antes, así que el pescado
  estibado sigue durmiendo dentro en vez de vibrar.
- La capacidad inicial es **250 kg**, editable por instancia con
  `capacidad_kg`.

`tests/bodega_tests.tscn` monta la bodega en el barco de verdad, le tira un
LEVIATÁN encima y exige deriva **cero** contra su socket, además de comprobar la
orientación del pizarrón. Era un fallo silencioso: la celda contaba kg igual de
bien, sólo que desde otro sitio.

## Comportamiento

El `Area3D` cuenta únicamente cuerpos `Fish` presentes físicamente. Al entrar
suma `peso_kg()`; al salir, ser recogido o abandonar la celda, lo resta. El
pizarrón muestra peso, capacidad y cantidad de peces. La tiza cambia a ocre a
partir del 75% y a rojo arcilla al alcanzar el límite. No usa pantalla, emisión
ni barra electrónica.

API pública:

- `kg`: peso actual.
- `cantidad_peces()`: piezas presentes.
- `esta_llena()`: compara el peso con `capacidad_kg`.
- señal `carga_cambiada(kg)`: publica cada entrada o salida para la futura
  cuota, interfaz o autoridad de red.
