# Fuente editable de los props de cubierta

## `bait_bucket.blend` — el balde de cebo

El juego consume `game/props/models/bait_bucket.glb`, instanciado por
`game/props/cubo_cebo.tscn`. Arte original del proyecto: no lleva mallas,
texturas ni materiales de terceros.

| Objeto | Papel | Quien lo toca en runtime |
|---|---|---|
| `BucketStaves` | duelas de roble + fondo encajado | nadie |
| `BucketIron` | los dos aros, las orejas y el asa volcada | nadie |
| `BaitFill` | la masa de cebo hasta el nivel | `cubo_cebo.gd` la **escala** |
| `BaitMound` | el copete: pellas, sardinas y gusanos | `cubo_cebo.gd` la **posa** |
| `BaitGaugeBase` / `BaitGaugeRim` | calibre `(radio, altura)` del interior util | `cubo_cebo.gd` los **lee** |

Tres cosas que hay que respetar al editarlo, porque son contrato con Godot y
`tests/fishing_tests.tscn` las vigila:

1. **Los nombres.** Renombrar un objeto en Blender deja el balde lleno para
   siempre, sin un solo error en consola.
2. **Los origenes.** `BaitFill` tiene el suyo en el FONDO del balde (se escala
   en Y y tiene que crecer hacia arriba, no desde el centro) y `BaitMound` en
   el PLANO DE LA SUPERFICIE (solo se traslada).
3. **El color por vertice** (`Col`, multiplicando al color base). Godot tine el
   cebo con el color del `TipoCebo`; si el moteado desaparece del GLB, el
   tinte pinta una masa plana y las sardinas dejan de distinguirse.

El cebo tambien tiene que caber en el balde a CUALQUIER nivel: la masa se
estrecha con la duela y el copete encoge al bajar. El generador lo comprueba al
exportar y los tests lo repiten en Godot.

## Regeneracion

Desde la raiz del proyecto:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' `
  --background --factory-startup --python tools\build_bait_bucket.py
```

Sobrescribe el `.blend`, el `.glb` y `docs/images/bait_bucket_preview.png`. La
geometria sale de una semilla fija (`SEMILLA`), asi que dos regeneraciones dan
el MISMO balde: si el GLB cambia, es porque alguien toco el generador.

Despues, reimportar con **Godot 4.7.2** (el `godot` del PATH es 4.6.1 y corrompe
los `.import`) y revisar el resultado en el motor:

```powershell
& 'C:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --import
& 'C:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path . tests/capture_cubo_cebo.tscn -- --shots-dir=<carpeta>
```
