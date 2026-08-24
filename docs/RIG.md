# El rig del pescador

Estado actual: **modelo smooth skineado** (2026-08-23). Fuente:
`source_assets/player/pescador_smooth.blend` · Generador:
`tools/build_pescador_smooth.py` · Runtime: `pescador_smooth.glb` · Tests:
`tests/rig_tests.tscn` (88 comprobaciones) · Controles visuales:
`tests/capture_anim.tscn` y `tests/capture_player_face.tscn`.

## Estado actual: soft low-poly con skin nativo

El personaje conserva sombrero verde, impermeable, barba gris, mitones y botas,
pero ya no son 37 bloques rígidos separados. Son 38 mallas suaves con una sola
`Skin`, 23 huesos y pesos mezclados en hombros, codos, cadera y rodillas. La
fuente editable y el GLB se regeneran juntos; las instrucciones y contratos
están en `source_assets/player/README.md`.

La importación usa `nodes/import_as_skeleton_bones=false`, el BoneMap humanoide
y `overwrite_axis=true`. Lo último no es decorativo: sin normalizar los ejes,
los clips retargeteados anteriores cargan, pero tuercen muñecas y piernas.

La cara suma diez morphs: parpadeo izquierdo/derecho, mirada en cuatro ejes,
sonrisa, tensión, habla y esfuerzo. `PlayerFaceAnimator` los conduce fuera del
`AnimationTree` corporal para no pelear por `Head` ni `Neck`.

La barba blanca en U y el bigote flotante ya no son mallas delante de la cara.
La barba corta gris es una segunda superficie de material dentro de `HeadMesh`;
por eso acompaña la piel sin volumen agregado. Ojos y pupilas son placas finas,
y la boca neutral es una línea baja que sólo abre lo necesario al hablar.

## Implementación histórica: pescador rígido

Lo que sigue documenta `pescador.glb` y `tools/rig_pescador.py`. Se conserva
como referencia y rollback, pero ya no es el asset instanciado por el jugador.

## Por qué un esqueleto de verdad (y no animar 37 nodos a mano)

- **Las animaciones que vienen**: idle, andar, nadar, lanzar/pelear con la caña,
  bombear, manguera, timón, cargar cajas (los verbos de DISENO.md).
- **Ragdoll de F4**: `PhysicalBoneSimulator3D` trabaja sobre huesos de un
  `Skeleton3D`, no sobre nodos sueltos.
- **Retarget**: cualquier clip humanoide (Mixamo, packs comprados) se mapea con
  un `BoneMap`... gratis SOLO si los huesos usan los nombres del perfil.
- **Red (F2)**: la copia del jugador que ven los demas se anima con el stream
  de poses de UN esqueleto.
- **Barba y sombrero**: `SpringBoneSimulator3D` (Godot 4.4+) para el meneo;
  tambien pide huesos.

## La decision que lo ordena todo: nombres de SkeletonProfileHumanoid

La doc oficial de retargeting pide al esqueleto objetivo: **T-pose**, mirando
**+Z**, sin transform a nivel de nodo, y **nombres ingleses del perfil** para
que el automapeo del BoneMap funcione. El pescador ya estaba en T-pose mirando
+Z; lo que NO tenia era jerarquia (botas hermanas de piernas, manoplas hermanas
de brazos: rotar el brazo no llevaba la mano) ni nombres. Eso es lo que arregla
el rig.

## Como esta montado (sin tocar un solo vertice)

1. `tools/rig_pescador.py` reescribe SOLO el grafo de nodos del chunk JSON del
   GLB: jerarquia plana -> cadenas articuladas con pivotes anatomicos.
   Idempotente (si ve "Hips" no hace nada) y con autochequeo de **paridad de
   mundos**: cada malla queda exactamente donde estaba (< 1e-5 m).
2. `nodes/import_as_skeleton_bones=true`: Godot convierte cada nodo del GLB en
   hueso de un unico `Skeleton3D` y cuelga cada malla de un `BoneAttachment3D`
   homonimo (verificado empiricamente; la doc no lo detalla).
3. Consecuencia: **skinning rigido de facto** — cada pieza 100 % a su hueso.
   Es a proposito: pesos suaves doblarian los cilindros y derretirian el look
   de bloques. Los huecos que se abren en codos y rodillas al doblar son parte
   del chiste (LEGO).

**TRAMPA conocida**: ahora hay un `BoneAttachment3D` con el MISMO nombre que
cada malla. `find_child("palma_R") as MeshInstance3D` devuelve null porque
encuentra antes el attachment. Siempre:
`find_children(nombre, "MeshInstance3D", true, false)`.

## EL ESPEJO (lo que mas cuesta ver)

El modelo mira a **+Z**. Con Y arriba en un sistema diestro, la derecha
anatomica es `adelante x arriba = Z x Y = -X`. El artista etiqueto sus mallas
`_L` en -X, o sea al reves. Por eso **los huesos `Right*` viven en -X y cargan
las mallas `*_L`**. Parece un bug y no lo es: si se "corrige", toda animacion
humanoide entra espejada — lo cazamos con el primer clip de Mixamo, que ponia
los brazos en la cara. `tests/rig_tests.tscn` lo fija con una comprobacion
explicita.

## El mapa (23 articulaciones + 37 mallas = 60 huesos)

| Hueso | Pivote (m) | Mallas colgadas |
|---|---|---|
| Root | 0, 0, 0 | — |
| Hips | 0, 0.55, 0 | — |
| Spine | 0, 0.78, 0 | — |
| Chest | 0, 0.95, 0 | chubasquero_cuerpo, tapeta, boton_1-3 |
| UpperChest | 0, 1.05, 0 | — (de aqui cuelgan cuello y hombros, como pide el perfil) |
| Neck | 0, 1.09, 0 | cuello |
| Head | 0, 1.12, 0 | craneo, nariz, cejas, ojos, boca |
| barba \* | 0, 1.12, 0 | barba_frente/menton/lados/uniones |
| sombrero \* | 0, 1.545, 0 | copa, ala |
| R/L Shoulder | ∓0.16, 1.00, 0 | — (clavicula: sin ella el brazo hereda el frame del pecho) |
| R/L UpperArm | ∓0.33, 1.00, 0 | brazo_geo |
| R/L LowerArm | ∓0.50, 1.00, 0 | puño (codo NUEVO: parte el brazo) |
| R/L Hand | ∓0.66, 1.00, 0 | palma |
| R/L UpperLeg | ∓0.20, 0.46, 0 | pierna_geo |
| R/L LowerLeg | ∓0.20, 0.26, 0.02 | bota_cana, bota_vuelta (rodilla) |
| R/L Foot | ∓0.20, 0.07, 0.04 | bota_puntera, bota_suela (tobillo NUEVO) |

\* extras fuera del perfil, cuelgan de Head. Sin dedos ni dedos de los pies:
el perfil los considera opcionales y este cuerpo no los tiene. En las filas
`R/L`, el signo `∓` va primero para la DERECHA (-X): ver "EL ESPEJO".

## Reglas para animar (la investigacion, destilada)

1. **Solo ROTACIONES en huesos.** Posicion unicamente en Hips (y Root si algun
   dia hay root motion). Retarget y ragdoll dependen de ello.
2. **Jamas escalar un hueso. Jamas renombrar uno** despues de la primera
   animacion: las pistas referencian por nombre.
3. La animacion **RESET** = la T-pose de descanso.
4. **AnimationTree** con state machine y **filtros de huesos** para partir
   arriba/abajo: las piernas andan mientras los brazos pescan o bombean.
5. **Clips externos (Mixamo y cia)**: el trabajo se hace EN EL IMPORT DEL CLIP,
   no en el rig — BoneMap sobre SkeletonProfileHumanoid + Rest Fixer:
   *Overwrite Axis* ("la opcion mas importante para compartir animaciones",
   doc oficial), *Fix Silhouette* si viene en A-pose, y Remove Tracks
   (*Unmapped Bones* + *Unimportant Positions*).
6. **La caña en 3ª persona/red**: `BoneAttachment3D` en RightHand. El viewmodel
   de 1ª persona sigue colgado de la camara; no compiten.
7. **Ragdoll F4**: `PhysicalBoneSimulator3D` sobre las articulaciones; las
   mallas siguen solas via sus attachments.
8. La camara de 1ª persona sigue SIN rotacion añadida (regla anti-mareo de
   `camera_feedback.gd`): las animaciones no tocan la camara, solo el cuerpo.

## El circuito Mixamo -> Godot (probado con `walk.fbx`, 2026-08-23)

**En Mixamo**: FBX Binary, **Without Skin**, 30 FPS, Keyframe Reduction None, y
**In Place** marcado (el cuerpo lo mueve `move_and_slide`, no la animacion).

**Import del clip** (`game/player/animations/walk.fbx.import`), lo que funciona:

```
"retarget/bone_map": Resource(".../mixamo_bonemap.tres")
"retarget/rest_fixer/overwrite_axis": true
"retarget/rest_fixer/normalize_position_tracks": true
"retarget/remove_tracks/unmapped_bones": true       # 53 pistas -> 21
"retarget/remove_tracks/unimportant_positions": true
"save_to_file/enabled": true -> walk_retargeted.res
```

**Import del modelo** (`pescador.glb.import`): el MISMO tratamiento con
`pescador_bonemap.tres` + `overwrite_axis`. Sin esto los ejes no coinciden y el
clip entra torcido. Verificado: el rest fixer compensa los `BoneAttachment3D`
rigidos — **ninguna malla se movio (desvio 0,0000 m)**.

**Trampas que costaron sangre:**

1. `remove_tracks/except_bone_transform` **borra TODAS las pistas** (errores de
   indice fuera de rango en el importador). No usarla.
2. `fbx/importer` tiene que quedar en **0 (ufbx nativo)**. En 1 llama a
   FBX2glTF, que no esta instalado: "Could not create child process".
3. Si un import falla, el `.import` queda con `valid=false` y Godot **no vuelve
   a intentarlo**: hay que borrar el `.import` y dejar que se regenere.
4. Con otra instancia de Godot abierta sobre el proyecto, los `.import` se
   pisan. Por eso la animacion se **hornea a `.res`**: `walk_retargeted.res` es
   un archivo de verdad, inmune a que el `.import` se regenere.
5. El BoneMap renombra el nodo del esqueleto a `GeneralSkeleton` y lo marca
   unico (`%`). Buscarlo por TIPO, nunca por nombre.
6. Las pistas del `.res` vienen como `%GeneralSkeleton:Hueso`; al montarlas en
   una escena instanciada hay que reescribir el prefijo al path relativo real
   (lo hacen `rig_tests.gd` y `capture_fishing.gd`).

## Fuentes

- Retargeting 3D Skeletons (doc oficial):
  <https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html>
- SkeletonProfileHumanoid:
  <https://docs.godotengine.org/en/stable/classes/class_skeletonprofilehumanoid.html>
- SpringBoneSimulator3D y RetargetModifier3D llegaron en Godot 4.4 (usamos
  4.6.1, asi que estan): <https://godotengine.org/article/dev-snapshot-godot-4-4-beta-1/>
