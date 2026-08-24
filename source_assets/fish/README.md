# Fuente editable de los peces comunes

`common_fish.blend` contiene las tres siluetas aprobadas para la banda A. El
juego consume los GLB separados de `game/fishing/models/`; la fisica sigue
viviendo en `game/fishing/fish.tscn`.

| Especie | Lectura principal | Peso base | Runtime |
|---|---|---:|---|
| Sardina | fina, plateada, una dorsal corta | 2 kg | `sardina.glb` |
| Caballa | torpedo verde azulado, bandas y dos dorsales | 3 kg | `caballa.glb` |
| Jurel | cuerpo alto, ojo grande y linea lateral dorada | 4 kg | `jurel.glb` |

Los tres modelos son arte original generado dentro del proyecto: no contienen
mallas, texturas ni materiales de terceros. Usan materiales PBR planos embebidos
y una sola malla por especie. Las aletas exageran la lectura; no forman parte de
la colision.

## Regeneracion

Desde la raiz del proyecto:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' `
  --background --factory-startup --python tools\build_common_fish.py
```

El comando sobrescribe deliberadamente la fuente `.blend`, los tres `.glb` de
runtime y la lamina `docs/images/common_fish_preview.png`. Despues hay que dejar
que Godot **4.7.2** reimporte los GLB; no usar el Godot 4.6.1 del `PATH`.

Convenciones:

- Blender: hocico hacia `+Y`, `Z` arriba, origen en el centro del pez.
- Godot/glTF: el hocico queda hacia `-Z`, `Y` arriba.
- Blender conserva la forma y los materiales.
- Godot conserva masa, capsula, flotabilidad y seleccion por especie.
