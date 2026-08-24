# Equipo modular del barco

Esta carpeta contiene las fuentes Blender de equipos que podrán instalarse en
los `UpgradeSockets` del barco, pero que no forman parte del GLB del casco.

## Bomba de achique manual

`manual_bilge_pump.blend` es el activo visual editable de la primera bomba. Su
dirección es tardomedieval, inspirada en la bomba de la nave de Newport: madera
ahuecada, lanza, cuero, hierro, cuerda y cesta-colador. Se
regenera con:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' `
  --background --factory-startup `
  --python 'tools\build_manual_bilge_pump.py'
```

Salidas:

- fuente: `source_assets/boat/equipment/manual_bilge_pump.blend`;
- runtime: `game/boat/equipment/models/manual_bilge_pump.glb`;
- presentación: `docs/images/manual_bilge_pump_preview.png`.

La bomba todavía **no está instalada en `fishing_boat.tscn`**. Su frente
funcional es `+Y` en Blender: palanca y testigo tallado miran al operador. Cuando se
integre en el socket de babor, ese frente debe quedar orientado hacia el pasillo
central y la descarga hacia la borda.

### Contratos de edición

- Las soleras de madera apoyan en `Z=0`; no desplazar el activo completo para
  corregir altura.
- Huella máxima: `0,70 × 1,00 m`, incluyendo el equipo almacenado.
- `LeverArm` conserva el origen en el eje de la palanca.
- `CadenceTongue` conserva el origen en el centro del testigo vertical.
- `IntakeHead` conserva el origen en el centro de su agarradera.
- `HoseAnchorArt`, `LeverPivotArt`, `CadencePivotArt` y
  `DischargeSocketArt` son empties exportados para cablear la escena Godot sin
  inferir coordenadas desde la geometría.
- `HoseCoil` solo representa la manguera guardada. Su propiedad
  `usable_length_m=6.8` documenta la longitud futura; la manguera extendida se
  generará en Godot para poder seguir la mano sin deformar el GLB.
- La manguera visual mide 55 mm de diámetro.
- El cabezal libre es la **aspiración**: una cesta de sauce lastrada.
  `DischargeDale` es la canaleta fija que más adelante mostrará agua y cavitación.
- La manguera móvil es una licencia de gameplay: se representa en cuero embreado
  y cáñamo porque una toma flexible larga no está documentada en esta bomba.
- El testigo de cadencia también es una licencia controlada; reemplaza el
  manómetro circular moderno por pesa, muescas y topes mecánicos.

Los nombres de objeto son API entre Blender y Godot. No renombrar `PumpBase`,
`PumpBody`, `IronHoops`, `PumpSpear`, `LeverArm`, `LeverGrip`, `CadenceRack`,
`CadenceTongue`, `IntakeCoupling`, `DischargeDale`, `HoseCradle`, `HoseCoil` ni
`IntakeHead` sin migrar también la escena de runtime.

Coordenadas de arte Blender en esta versión:

| Anclaje | Posición XYZ |
|---|---:|
| `HoseAnchorArt` | `(-0.332, 0.000, 0.245)` |
| `LeverPivotArt` | `(0.000, 0.000, 0.910)` |
| `CadencePivotArt` | `(0.205, 0.213, 0.690)` |
| `DischargeSocketArt` | `(0.318, 0.085, 0.612)` |
| origen de `IntakeHead` en reposo | `(0.200, -0.270, 0.583)` |
