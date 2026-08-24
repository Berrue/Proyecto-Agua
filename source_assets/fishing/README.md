# Fuente editable de la caña

`fishing_rod.blend` es el modelo de la caña que el jugador tiene en la mano. El
juego consume `game/fishing/models/cania.glb`; la lógica (lanzar, picada, lucha,
sedal, tiers) sigue viviendo en `game/fishing/fishing_rod.gd`.

Es arte original generado dentro del proyecto con
`tools/build_fishing_rod.py`: no contiene mallas, texturas ni materiales de
terceros. Un mesh por pieza, materiales PBR planos embebidos, 1206 vértices /
2248 triángulos en total, más un rig de seis huesos que curva el cuerpo.

## Por qué tiene las piezas que tiene

Antes eran dos cilindros y una esfera de bloqueo gris. La caña es lo que el
jugador mira TODO el rato — en primera persona ocupa media pantalla y sale en
cuadro en cada estado del sistema —, así que cada pieza está para que se
entienda un gesto de un vistazo:

| Nodo en Godot | Qué es | Por qué está |
|---|---|---|
| `Blank` | Cuerpo naranja + hilo del encaje, con 18 anillos de vértices | El naranja de seguridad se lee contra los tres fondos del juego (mar gris, cielo, cubierta); el escalón entre tramos rompe la silueta de "palo"; los anillos son lo que le permite CURVARSE en vez de quebrarse |
| `Guides` | Seis anillas escalonadas + puntera | Escalonar de gorda a fina es lo que dice "caña" desde tres metros, y es la única línea de detalle que sobrevive al low poly |
| `Grip` | Empuñadura DELANTERA | Es la pieza que `FishingRod._apply_tier()` tinta con el color del tier. Va entera por debajo de donde arranca el rig: es rígida, y cruzarlo la estiraría |
| `RearGrip` | Empuñadura trasera + taco de culata | Se ve en tercera persona, en el soporte de borda y en el suelo |
| `ReelSeat` | Portacarretes: cuerpo, capuchones, tuerca | El negro + cromo del mango, y lo que explica que ahí haya un carrete atornillado |
| `ReelBody` | Pie, columna y cuerpo del carrete | — |
| `ReelRotor` | Rotor, bobina, hilo y arco | Origen EN EL EJE de la bobina: Godot puede girarlo al recoger sin tocar la malla |
| `ReelHandle` | Manivela y pomo | Origen en el eje de la manivela (local X), por lo mismo |

## El rig del doblez

`CaniaRig` son seis huesos (`Cania_0` … `Cania_5`) en cadena, del arranque del
cuerpo (z = 0,155) a la punta. Solo el cuerpo y las anillas están enganchados:
mango, portacarretes y carrete son hierro y corcho, y una pieza rígida que se
estira delata el truco antes que cualquier otra cosa.

Los pesos son una función sombrero calculada en el script (cada vértice reparte
entre los dos huesos más cercanos), no `ARMATURE_AUTO`: la geometría la genera
este mismo script, así que se pueden calcular exactos en vez de adivinarlos, y
no dependen de la versión de Blender de quien regenere el modelo.

Quien reparte la curva es Godot (`FishingRod`): `BEND_RIGID_SHARE` decide cuánto
del doblez es la caña entera inclinándose y cuánto es el cuerpo arqueándose, y
`BEND_BONE_WEIGHTS` cómo se reparte el arco entre los seis huesos — cargado
hacia la punta, que es como dobla una caña de acción rápida. **El nodo `Tip` no
copia esa curva: la lee del último hueso**, así que cambiar los pesos no
descoloca el nacimiento del sedal. Para mirar la curva sin depender de la
tensión de una partida: `tests/capture_cania.tscn`.

Tres números no son estéticos y no se tocan a ojo:

- **La punta cae en `y = 1.54`**, que es donde `RodPivot/Tip` ancla el sedal.
  Moverla hace que el sedal nazca en el aire. `tests/fishing_tests` lo comprueba
  contra la caja real de la malla, así que si el perfil cambia, salta.
- **La empuñadura del tier va DELANTE de la mano** (`Player.arm_grip = 0.05`).
  El brazo del viewmodel es una cápsula de 7 cm de radio que se traga todo lo
  que quede por detrás: pintar la trasera era pintar algo invisible.
- **El carrete cuelga 10.5 cm bajo el eje**, o sea fuera de esa cápsula. Y la
  caña rueda sobre su propio eje en el viewmodel (`FishingRod.model_roll_deg`)
  para que asome por la izquierda del brazo en vez de quedar detrás.

## Regeneración

Desde la raíz del proyecto:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' `
  --background --factory-startup --python tools\build_fishing_rod.py
```

Sobrescribe deliberadamente la fuente `.blend`, `game/fishing/models/cania.glb`
y las dos láminas de `docs/images/` (`fishing_rod_preview.png` y
`fishing_rod_detalle.png`). Después hay que dejar que Godot **4.7.2** reimporte
el GLB; no usar el Godot 4.6.1 del `PATH`.

El script se valida a sí mismo antes de exportar: si falta una pieza, si la
punta se sale de `1.54`, si una anilla se despega del cuerpo o si el carrete se
mete dentro del brazo, revienta con el motivo en vez de exportar un GLB roto.

Convenciones:

- Blender: la caña corre a lo largo de `+Z` (culata abajo) y el vientre —
  carrete y anillas — mira a `+Y`.
- Godot/glTF: `+Z` pasa a `+Y` y `+Y` pasa a `-Z`; la caña apunta hacia arriba
  dentro de `RodPivot` y el carrete queda por debajo y hacia delante.
- El origen (0,0,0) es el punto de agarre: el GLB entra en la escena sin
  transform.
