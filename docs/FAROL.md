# El farol de tormenta

Estado: **funcionando** (2026-08-23). Código: `game/props/farol.gd` (subclase de
`Portable3D`, ver [PORTEO.md](PORTEO.md)) · `game/props/gancho_farol.gd` ·
Tests: `tests/farol_tests.tscn`.

La única luz portátil de la noche (DISENO.md §2, "roles-objeto"). No es una
linterna: es un ROL que se lleva en la mano — quien porta el farol es quien
decide qué se ve, y dejarlo colgado en un gancho es una decisión de
infraestructura ("esta zona queda iluminada, esta mano queda libre").

## Las cinco decisiones cerradas

1. **No se gasta ni se apaga.** Sin aceite, sin batería, sin reencender. El mar
   ya administra la tensión; una barra de combustible añadiría mantenimiento
   que compite por manos y castigaría en la oscuridad, justo donde el castigo
   no se ve venir (regla 8: todo fallo se telegrafía antes de castigar).
2. **Ocupa UNA mano** (`manos = 1`). Andás, saltás y te agarrás con el farol;
   lo que no podés es tocar la caña o la bomba sin colgarlo o soltarlo.
3. **Una sola luz con sombras en toda la escena**: la del farol que lleva el
   jugador LOCAL en la mano. Una omni con sombras rinde su mapa cada vez que
   algo se mueve — y acá se mueve todo, siempre. Las demás llevan
   `distance_fade` (los dos van juntos: el fade solo ahorra con sombras
   apagadas, godot#88085).
4. **El parpadeo es función pura de `Ocean.sim_time`** (tres senos no
   múltiplos). La llama respira a ~6,4 Hz, se agita con la furia (telegrafía
   periférica gratis) y se congela al pausar la simulación. Perdido en el
   agua, cambia a **cadencia de socorro** ~1 Hz (código LSA 2.2.3): un
   accidente se vuelve una llamada de auxilio legible desde el barco, sin HUD.
5. **El farol NO es la telegrafía.** Ayuda a ver de cerca; el aviso del
   tsunami vive donde ya vive. Si ver el muro dependiera de llevar luz, la
   noche pasaría de difícil a injusta.

## Los ganchos

`GanchoFarol` (dos de serie en el frente de cabina del pesquero, uno por
banda). Son la mitad del diseño: sin ellos el objeto obliga a elegir entre luz
y manos todo el rato, que cansa. El farol colgado **pendulea con la
aceleración real del gancho** (muelle amortiguado ~1,1 Hz con tope): las
sombras de toda la cubierta se mecen con el mar, y esa lectura periférica no
puede mentir porque sale de la física, no de un script.

La `Zona` (Area3D) del gancho vive en la capa 1 **a propósito**: es el blanco
del rayo del `Portador` para colgar y descolgar. Nació en capa 0 y ningún rayo
la veía — colgar era imposible y no había ni un warning; hoy lo protege un
test (`porteo_tests`).

## Dónde está cada cosa

- El farol arranca **suelto en cubierta** junto a la cabina (toybox y
  tsunami). Rueda con la escora desde el segundo cero: eso es contenido, no un
  bug. Si un playtest pide que arranque colgado, se cambia en la escena.
- Sus sombras las gobierna `_actualizar_sombras()` vía el hook
  `_tras_cambio()` de `Portable3D` — al generalizar el porteo, la invariante
  de "una sola sombra" siguió viviendo en el farol, que es el único al que le
  importa.
