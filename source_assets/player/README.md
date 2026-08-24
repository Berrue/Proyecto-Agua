# Fuente del pescador

El personaje activo se genera de forma reproducible desde
`tools/build_pescador_smooth.py`. El script crea, en paralelo al modelo
histórico:

- `source_assets/player/pescador_smooth.blend`: fuente editable.
- `game/player/pescador_smooth.glb`: asset importado por Godot.
- PNG de control en `%TEMP%/pescador_smooth_qa` o en `PESCADOR_QA_DIR`.

Desde la raíz del proyecto, con Blender 5.1:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' `
  --background --factory-startup --python tools/build_pescador_smooth.py
```

Después hay que reimportar con Godot 4.7.2. El `.import` usa skinning nativo
(`nodes/import_as_skeleton_bones=false`), el `pescador_bonemap.tres` y
`overwrite_axis=true`; estas dos últimas opciones son necesarias para que los
clips corporales existentes no entren con muñecas y piernas torcidas.

Contratos que no deben cambiar al retocar el `.blend`:

- un solo armature y los 23 huesos actuales, con nombres humanoides exactos;
- T-pose mirando `+Z` una vez importada en Godot;
- `palma_R` y `palma_L`, usados por el brazo de primera persona;
- morphs `blink_L`, `blink_R`, `look_left`, `look_right`, `look_up`,
  `look_down`, `smile`, `tense`, `talk` y `effort`;
- mallas faciales `Eye_L/R`, `Pupil_L/R`, `Brow_L/R` y `FaceMouthMesh`; el
  nodo `Mouth` queda como alias estable, sin geometría.
- 38 mallas skineadas: la antigua `Beard` volumétrica y los bigotes flotantes no
  existen; la barba gris es una superficie de material de `HeadMesh`.

`legacy/pescador_rigid_before_smooth.glb` es la copia previa a esta migración.
No se regenera ni se sobrescribe desde el builder nuevo.
