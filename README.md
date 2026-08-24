# Proyecto Agua

Supervivencia cooperativa (2-6 amigos) a bordo de un pesquero, en un mar que escala
de la calma al tsunami. **El agua es el antagonista**: un océano determinista y
consultable en el futuro, así que el aviso nunca miente y la dificultad jamás se
ajusta a escondidas.

## Abrir y jugar

Godot **4.7.2** (`C:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe` — ojo, el
`godot` del PATH es un 4.6.1 viejo). Escenas de entrada:

- `game/world/toybox.tscn` — el juguete: barco, caña, HUD de furia con
  lanzador de tsunamis (teclas 1-3, 0 cancela).
- `game/world/tsunami.tscn` — la secuencia dirigida: calma → tormenta → retirada
  → aviso → impacto → resaca, con los tres tiers en ciclo.

## Tests

Los arneses headless salen con código ≠ 0 si algo falla. **La lista completa y al día está en
`CLAUDE.md`** (hoy son 25); aquí van solo unos cuantos de ejemplo, porque duplicar la lista fue
exactamente lo que hizo que esta línea dijera «siete» durante meses mientras en `tests/` había 25:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . tests/f1_tests.tscn
```

(idem `tsunami_tests`, `fishing_tests`, `day_night_tests`, `hud_launcher_tests`,
`music_tests` y `boat_asset_tests`).
Los `capture_*.tscn` generan capturas de revisión, no son tests.

## Documentación

| Archivo | Qué cuenta |
|---|---|
| `CLAUDE.md` | Las reglas del repo: invariantes, convenciones, cómo trabajar aquí |
| `docs/DISENO.md` | El diseño de juego completo (loop, roles, economía, dificultad) |
| `docs/DECISIONES.md` | Decisiones técnicas cerradas, y las abiertas con su porqué |
| `THIRD_PARTY.md` | Licencias: qué puede entrar al repo y qué está en lista negra |

Cada archivo de código lleva su cabecera `##` explicando qué papel juega y qué
reglas protege — leerla antes de tocar el archivo.
