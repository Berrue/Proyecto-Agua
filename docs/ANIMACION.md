# Animación del pescador

Estado: **funcionando** (2026-08-23). Árbol: `game/player/player_animator.gd` ·
Clips: `game/player/animations/*_retargeted.res` · Tests:
`tests/anim_tests.tscn` (26 comprobaciones) · Fotos: `tests/capture_anim.tscn`.

El rig y el circuito de retarget están en [RIG.md](RIG.md). Esto es lo que pasa
**después**: cómo se mezclan los clips y quién manda sobre cada hueso.

## Cara aditiva

`game/player/player_face_animator.gd` agrega una segunda capa que sólo escribe
morphs y piezas faciales: parpadeo, micro-miradas, sonrisa, preocupación,
habla y esfuerzo. Se monta automáticamente junto al `PlayerAnimator` y deriva
esfuerzo/tensión de locomoción, agua y caña, por lo que las copias remotas
reaccionan al estado que ya reciben sin sumar otro RPC.

La API pública permite además `set_speaking`, `set_expression`, `set_effort`,
`play_emote` y `look_toward`. Las poses deterministas se prueban en
`tests/player_face_animator_tests.tscn` y se renderizan con
`tests/capture_player_face.tscn`.

## Por qué animar un cuerpo que no se ve

En primera persona el cuerpo está en solo-sombra, así que esto no anima "lo que
ves". Anima dos cosas que sí importan:

1. **Tu sombra en cubierta**, que es información — te dice dónde estás parado y
   qué estás haciendo.
2. **La copia tuya que verán los demás** cuando entre la red en F2. Montar el
   árbol después, con la red encima, sale mucho más caro.

## El árbol

```
idle ────────────┐
                 ├─ locomotion ─┐
walk ─ TimeScale ┘  (por veloc.) ├─ water ─┐
                                 │ (por     ├─ rod ── salida
swim ────────────────────────────┘ sumersión)│  (Blend2 FILTRADO)
fishing_idle ────────────────────────────────┘
```

| Parámetro | Qué lo mueve | Rango |
|---|---|---|
| `parameters/locomotion/blend_amount` | velocidad / `walk_speed` | 0 = idle, 1 = walk |
| `parameters/walk_scale/scale` | la misma velocidad | 0,7 → 1,8 (cadencia del paso) |
| `parameters/water/blend_amount` | sumersión del cuerpo | 0 = cubierta, 1 = flotando |
| `parameters/rod/blend_amount` | `input_captured` (la lucha) | 0 = libre, 1 = caña |

Todo se suaviza con `blend_speed` (8/s): sin eso los cambios de estado leen
como cortes de montaje.

**Ojo con `input_captured` vs `hands_busy`**: la pose de caña la dispara *la
lucha* (`input_captured`), no el recuento de manos. `hands_busy` es
`input_captured or hands_used >= 2`, así que cablear `hands_busy` haría que
cargar un fletán a dos manos ponga pose de PESCAR. Hay un test dedicado
("cargar algo a dos manos NO pone pose de pescar") porque es un cambio que se
ve razonable al leerlo.

## El filtro es el pilar, no un adorno

`rod` es un `Blend2` **con filtro de huesos**: la caña manda sobre **los brazos
y la mirada** (hombros, brazos, manos, cuello, cabeza); el torso y las piernas
siguen siendo de la locomoción.

La regla: el torso pertenece a lo que estás *haciendo con el cuerpo* (caminar,
flotar), los brazos a lo que tenés *en las manos*.

**Medido, porque acá el ojo miente.** Nadando, el pescador se ve muy inclinado
hacia adelante, y es tentador culpar al filtro. No lo es: el clip *Treading
Water* de Mixamo ya viene con el cuerpo a **33,5° de la vertical sobre su propio
esqueleto**, y sobre el nuestro da 36,3° — el retarget aporta 3°. Meter
`Spine/Chest/UpperChest` en el filtro mueve la postura del torso **6 mm**
(`chest-hips` 0,318 vs 0,324). O sea: la diferencia entre "nadando" y "nadando
con caña" son los brazos, no el tronco. El filtro quedó en brazos-solo por
coherencia, no porque arreglara nada.

Los tests fijan dos cosas: que la caña no cambie la postura del torso (con y sin
caña difieren < 3 cm) y que conserve más del 72 % de su altura cadera-pecho en
rest. El umbral es relativo porque el torso smooth es deliberadamente más
petiso que el anterior. Eso es exactamente
la regla de diseño *"las dos manos ocupadas: pescar te quita el agarre"* — el
pescador sigue trastabillando con las piernas mientras los brazos están
comprometidos. `tests/anim_tests.tscn` lo comprueba midiendo las dos mitades a
la vez: manos por delante del pecho **y** zancada viva en el mismo frame.

Y lo comprueba **por el camino real** (`velocity` / `input_captured` →
`_feed_animator` → `update`), no sólo por el helper `force()` de los tests: una
revisión con mutation testing demostró que `update()` podía ignorar la caña
entera y las 19 comprobaciones de entonces seguían en verde.

Detalle que costó un test en rojo: "por delante" se mide **en el marco del
pecho**, no en Z de mundo. Nadando, el torso se echa hacia atrás y una pose de
caña perfectamente válida daba "detrás" en coordenadas de mundo.

## El agua entra por una rampa, no por un interruptor

`water` **no** está atado al estado `SWIMMING`: se calcula con
`smoothstep(swim_threshold - 0.2, swim_threshold, submerged_fraction)`, o sea
que la mezcla empieza a colarse cuando el agua te llega al muslo y está completa
cuando pasás el umbral de nadar. Vadear y nadar son el mismo gesto continuo; un
corte seco justo en el umbral se lee como un bug de estado, no como física.

El nodo `water` **no está filtrado**: flotando no hay cubierta que pisar, así
que la locomoción entera deja de tener sentido. Pero va **antes** que `rod`, y
eso es deliberado: si te caés al mar peleando un pez, las manos siguen en la
caña mientras las piernas patalean.

## La trampa de la velocidad (medida, no supuesta)

El árbol se alimenta de `velocity` **tal cual**. Parece que sobre un barco en
marcha habría que restarle `get_platform_velocity()`. **No.** Medido en el
toybox con el jugador quieto sobre cubierta:

```
vel=(0.00, 0.00, 0.00)   plataforma=(0.12, 0.20, 0.16)
```

Godot ya arrastra al `CharacterBody3D` con la plataforma sin tocarle la
velocidad. Si se resta, el pescador "camina" con cada ola y la mezcla vibra con
el balanceo. Hay un test dedicado a esto (`_test_no_camina_por_el_balanceo`)
que sube la furia a 4 y exige que la mezcla se quede bajo 0,1.

## Agregar un clip nuevo (3 pasos)

1. Bajarlo de Mixamo: FBX Binary, **Without Skin**, 30 FPS, Keyframe Reduction
   None, **In Place**. Copiarlo a `game/player/animations/<nombre>.fbx`.
2. `"C:/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe" --headless --import --path .`
   (genera el `.import`), después `python tools/import_clip.py` y volver a
   importar. Queda horneado como `<nombre>_retargeted.res`.
   **NUNCA el `godot` pelado del PATH**: en esta máquina es un 4.6.1 viejo que
   reescribe los `.import` borrando claves que sólo conoce 4.7.2. No da error;
   el daño sólo se ve en `git status`.
3. Sumarlo a `CLIPS` en `player_animator.gd` y engancharlo al árbol.

## Lo que falta (a propósito)

- **Bajo el agua** usa el mismo clip que flotar (`Treading Water`). Cuando el
  buceo sea un verbo de verdad merece el suyo.
- **Los pies patinan** un poco: no hay root motion, la cadencia sólo se estira
  con `TimeScale`. Decisión consciente — root motion sobre una cubierta que se
  mueve es un problema mucho más grande que el patinaje.
- **La caña tiene un solo clip** (`fishing_idle`). Picada y lucha merecen los
  suyos; el hueco ya está en el árbol.
- **Barba y sombrero** siguen rígidos: son huesos, así que
  `SpringBoneSimulator3D` los puede menear cuando queramos.
