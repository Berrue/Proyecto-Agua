# Peces tier 1 tardío — fuente aprobada

Esta carpeta contiene **Boquerón, Faneca y Sargo**, los tres peces que completan
el tier 1 según la escalera de `docs/PESCA.md`.

## Estado

**Aprobados e integrados al juego.** Los GLB maestros de esta carpeta se
conservan en `staged_glb/`, bajo `source_assets/.gdignore`; las copias de runtime
viven en `game/fishing/models/` y las tres especies ya apuntan a ellas mediante
`visual_scene`.

| Especie | Lectura principal | Peso | Furia | Tris |
|---|---|---:|---:|---:|
| Boquerón | muy fino, boca larga y franja azul | 1 kg | 1,5+ | 212 |
| Faneca | cuerpo cobrizo, barbilla, tres dorsales y dos anales | 2 kg | 1,5+ | 264 |
| Sargo | cuerpo alto plateado, cinco barras y mancha caudal | 4 kg | 2+ | 268 |

Las aletas pectorales usan una raíz facetada de tres puntos hundida dentro del
cuerpo. Dorsales, anales y colas también empiezan dentro del volumen: no hay
hojas tangentes apoyadas sobre una superficie redondeada.

Las franjas, manchas y líneas laterales están teseladas y proyectadas sobre las
cuadernas del cuerpo; no son placas planas separadas de la superficie curva.

## Regeneración

Desde la raíz del proyecto:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' `
  --background --factory-startup --python-exit-code 1 `
  --python tools\build_tier_1_late_fish.py
```

El comando genera:

- `tier_1_late_fish.blend` — fuente editable;
- `staged_glb/{boqueron,faneca,sargo}.glb` — maestros aprobados para exportación;
- `docs/images/tier_1_late_fish_preview.png` — perfiles;
- `docs/images/tier_1_late_fish_attachments.png` — vista tres cuartos de uniones.

Son modelos originales del proyecto, con un máximo de seis materiales planos
embebidos por pez y sin
texturas, animaciones, esqueletos, luces, cámaras ni física exportada.

La integración se validó con 76/76 comprobaciones específicas de assets y
136/136 comprobaciones del sistema de pesca. La captura de los modelos ya
importados está en `docs/images/godot_fish/tier_1_late_fish_runtime.png`.
