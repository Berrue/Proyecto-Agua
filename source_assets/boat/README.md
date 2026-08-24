# Fuente editable del pesquero modular

`modular_fishing_boat.blend` es la fuente de arte. El juego consume
`game/boat/models/modular_fishing_boat.glb`.

## Edición rápida

1. Abrir el `.blend` en Blender 5.1 o compatible.
2. Editar los objetos dentro de la colección `EXPORT`.
   `HullShell` está modelado a media manga y usa `Simetria editable` (Mirror),
   por lo que conviene mover vértices del lado existente sin aplicar el modificador.
   `Transom` es el cierre de popa independiente: puede reemplazarse para montar
   motor, timón o escala sin cortar el casco longitudinal.
3. Mantener el origen del barco en `(0, 0, 0)`, la proa hacia `+Y` de Blender y
   la cubierta aproximadamente en `Z = 0.80`.
4. Exportar solo `EXPORT` como glTF binario sobre el GLB de `game/boat/models/`.
5. Volver a Godot 4.7.2 y dejar que reimporte.

La colección `SOCKET_GUIDES_NOT_EXPORTED` replica visualmente los anclajes que
viven en `fishing_boat.tscn`. Los sockets reales se mueven en Godot, no en el
GLB, porque así no se pierden al reexportar. El generador **lee** esas posiciones
del `.tscn` en cada pasada: no hay una segunda lista que mantener a mano, y por
eso la guía nunca puede quedarse en una manga vieja.

`BUOYANCY_GUIDES_NOT_EXPORTED` replica las ocho sondas físicas. Si una esfera
queda fuera del casco tras una edición, hay que corregir la malla o revalidar la
flotación en Godot; las guías tampoco se exportan.

## Regeneración paramétrica

Desde la raíz del proyecto:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' `
  --background --factory-startup --python tools\build_modular_boat.py
```

Esto sobrescribe deliberadamente el `.blend`, el `.glb` y el render de
documentación. Usarlo solo cuando se quiera volver al blockout generado.
