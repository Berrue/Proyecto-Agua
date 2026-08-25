# Porteo — agarrar, llevar, soltar, lanzar, estibar

Estado: **fase A funcionando** (2026-08-23). Código: `game/props/portable.gd`
(la base), `game/player/portador.gd` (las manos), `game/ui/porteo_hud.gd` (el
prompt), `game/boat/bodega.gd` (la estiba). Tests: `tests/porteo_tests.tscn` y
`tests/farol_tests.tscn`. El farol ([FAROL.md](FAROL.md)) fue el prototipo;
esto es su generalización.

## Qué es (y qué NO es)

**Este juego no tiene inventario de grilla.** Lo decidió DISENO.md antes de
que existiera el código: el rol es "la estación donde estás parado o **el
objeto que llevás en las manos**", la carga suelta está en riesgo hasta el
puerto, y el barco es el HUD. Un bolsillo mágico de 4 huecos disolvería la
tesis del déficit de manos y le quitaría a la ola el derecho de arrancarte lo
que llevás.

**Decisión del usuario (2026-08-23): manos + cinturón chico.**

- **Las manos** son el inventario principal: 0, 1 o 2 ocupadas, siempre a la
  vista de todos. Un objeto a la vez.
- **El cinturón** (fase B) tendrá 1-2 huecos SOLO para objetos chicos
  declarados (`en_cinturon`): la radio, la llave del motor. Nunca peces, nunca
  herramientas grandes. Es calidad de vida, no un escape de la tesis.
- Lo demás vive donde el diseño manda: **la cubierta** (rigidbodies sueltos,
  en riesgo), **los ganchos** (el farol), **la bodega** (la cuota física).

## Principios

1. **Lo que llevás se VE.** En tus manos, en las de los demás, y mañana en la
   red. El HUD solo enseña el botón (doctrina de la UI de pesca: primero se
   aprende, luego se presume).
2. **Rígido con la vista, jamás con muelle.** En mano el objeto va congelado
   (freeze kinemático, capa 0) colgado del marker de la cámara: cero retraso.
   Un joint sobre una cubierta que cabecea "te persigue" y se siente de goma.
   El corolario que no se negocia: congelado = `_physics_process` apagado, o
   el empuje del océano se acumula en silencio y el objeto sale disparado al
   soltarlo.
3. **Soltar hereda tu velocidad; lanzar ES soltar con más.** Sin eso el objeto
   queda flotando donde estabas y el mundo parece hacer trampas.
4. **El déficit de manos es el diseño.** 1 mano: seguís entero. 2 manos:
   caminás (lento, `carry_slowdown`), pero sin salto y sin caña. La LUCHA de
   la caña es otra cosa: captura el input entero (`input_captured`). Portear
   nunca te clava en el sitio — regla 6: si el input deja de producir efecto,
   se siente roto, no difícil.
5. **La estiba cuenta por presencia física, no por snap.** El pez en la celda
   sigue siendo un cuerpo: rueda con la escora, reparte peso, y una ola grande
   puede sacarlo. Un pez EN LA MANO no cuenta (capa 0): la cuota es honesta
   sin una línea especial.
6. **El estado replicable de un portable son SEIS datos**, no «dos ids y un
   enum» como prometía este documento antes de implementarlo: id del cuerpo,
   estado, peer del portador, **índice** de socket (los dos `SoporteCania` del
   barco se llaman igual: el nombre no basta), hueco de cinturón, y para
   `SUELTO` el transform con su bit de marco. Más, para el pez, el índice de
   especie. Todo lo demás es presentación local. La transferencia de autoridad
   al agarrar se colgó de `tomar()`/`soltar()` sin redibujar nada, tal como
   estaba previsto.

## El contrato técnico

| Pieza | Papel |
|---|---|
| `Portable3D` (extiende `FloatingBody3D`) | Los verbos: `tomar(portador, agarre)`, `colgar_en(gancho)`, `soltar(en, velocidad)`. Declara `manos` (1-2), `nombre`, `colgable`, `peso_kg()`. Hook `_tras_cambio()` para subclases (el farol mueve ahí su sombra). |
| `Portador` (bajo la `Camera3D` del player) | Un rayo (2,2 m), dos markers (una mano: abajo-derecha; dos manos: abrazo centrado), el cinturón (dos `Cinto*` a la cadera del Player), la contabilidad de manos y el HUD. `factor_lentitud(kg)` es estática y pura. |
| `SoporteCania` (uno por banda, sockets `Gear*`) | El patrón del gancho aplicado a la caña: `Zona` para la mira y ocupar/liberar. **La caña de verdad SE MUDA aquí** (24-ago-2026): `FishingRod` reparenta su `RodPivot` a la `Cuna` del soporte, así que la caña clavada es la misma —con su sedal enhebrado, su aparejo y su carrete— y no una copia gris. Ahí empieza la partida: la caña nace en el barco y hay que ir a por ella. |
| `Player` | Tres números que otros escriben: `hands_used` (0-2, porteo), `input_captured` (la lucha), `carry_slowdown`. `hands_busy` queda como lectura histórica: lucha O dos manos llenas. |
| `FishingRod` | `_hands_free()`: con carga en brazos no hay caña — ni lanzar, ni recoger, ni clavar. Si la picada llega con las manos llenas, el pez se va sin castigo: recoger algo en plena espera fue TU apuesta. |
| `Bodega` (AnimatableBody3D anclado al socket `HoldAft`, `sync_to_physics` off) | Celda medieval de roble y hierro + `Zona` que suma/resta kg al entrar/salir + pizarrón de tiza con peso y piezas. Señal `carga_cambiada(kg)` para la cuota futura. |
| `CuboCebo` (mobiliario de cubierta, babor) | El patrón del soporte aplicado al cebo: `Zona` para la mira y `E` para llenar el anzuelo. El nivel del balde ES el contador (baja con las cargas, se tiñe del cebo). Ver [PESCA.md](PESCA.md) §5. |
| `PorteoHud` | UN prompt contextual (Atkinson, abajo-centro) y la barra de carga del lanzamiento. Nada más. |

**Controles.** `E` es todo el porteo: agarrar / colgar / soltar — y sobre un
soporte de borda, clavar o retomar la caña. El click (que la caña cede al
tener las manos ocupadas) **carga y lanza**: tap = empujoncito, mantener =
pasarle la sardina al de la borda. El empuje útil cae con el peso — un atún
no se lanza, se deja caer con intención. `Q` es el cinturón: guarda lo que
llevás (si es chico) y saca lo último guardado (LIFO).

**Los números de feel** (todos en `portador.gd` y `fish.gd`, con su porqué):
umbral 1↔2 manos entre el jurel y la lubina (6 kg — toda la banda B
compromete las manos); lentitud 1,0 → 0,85 (fletán) → 0,4 (atún), con suelo en
0,3; carga de lanzamiento 0,85 s.

## Fases

- **A — El verbo y su primer cliente (HECHA).** `Portable3D` extraído del
  farol; `Portador` general; el pez portable (peso de especie = manos y
  lentitud); lanzar con carga; bodega física en `HoldAft` contando kg; prompt
  mínimo; candados caña↔manos; tests. El loop del día 1 queda entero:
  pescar → izar → portear → estibar.
- **B — El cinturón y los roles-objeto (HECHA).** Cinturón de DOS huecos
  (`Q` guarda / `Q` saca, LIFO), solo para objetos chicos declarados
  (`en_cinturon`), con su tira mínima abajo-derecha; los portables van
  VISIBLES a la cadera (principio 1). A bordo: la **radio portátil** (flota,
  muda por ahora — su audio va por ElevenLabs), la **llave del motor** (SE
  HUNDE: perderla al agua es una misión, el patrón cámara de Content
  Warning), la **caja de herramientas** y el **bichero** (dos manos; su
  función llega con el achique y los rescates). Y el **soporte de borda**:
  la caña se clava con E y PESCA SOLA — espera, toques y mordisco siguen
  corriendo; la señal de estación es el chomp 3D, el "!" sobre la boya y la
  caña doblándose en la borda con su muelle REAL (regla 8: no puede mentir);
  retomarla dentro de la ventana es el minijuego de haberla dejado. **Esa
  ventana es propia** (`BITE_WINDOW_SOPORTE`, 3,5 s frente a los 1,8 s de la
  caña en mano): medida contra la cubierta real, reaccionar + cruzar 4,74 m +
  apuntar + retomar pide ~2,1 s, así que con la ventana de mano la caña
  clavada pescaba sola *para que el pez se fuera siempre*. Ver
  [PESCA.md](PESCA.md) §4 paso 2; `fishing_tests` protege el margen contra la
  geometría del barco. De paso
  quedó saldada la deuda del viewmodel: la caña se guarda sola mientras
  porteás. El pez con la picada llegando y las manos llenas se va SIN
  castigo: soltar la caña de las manos fue tu apuesta.
- **C — La red (HECHA, dentro de R1 · `docs/RED.md`).** El porteo entero
  viaja: `pedir_porteo` → el host arbitra con `NetPorteo.arbitrar` (una
  función pura y testeada, porque `Net` es un autoload singleton y dentro de
  un RPC no habría forma de probar ni una regla) → `aplicar_porteo` a todos, o
  `porteo_denegado` al que perdió, con texto que el HUD dice. **Agarre
  pesimista** por la regla 8. La carrera de dos jugadores la resuelve el orden
  total del host: gana el primero que entra.

  De paso salieron a la luz cuatro bugs que ya existían **sin red** y que el
  camino del jugador escondía: `colgar_en` no desenganchaba el gancho anterior
  ni ocupaba el nuevo; `soltar` no comprobaba quién soltaba (cualquiera podía
  soltar el objeto de cualquiera); el congelado se guardaba dentro el empuje
  del océano de antes del agarre; y **los markers del cinturón nunca
  existieron en la escena real** — Godot rechaza `add_child` sobre un padre que
  todavía está montando sus hijos, así que el `_ready` del Portador los creaba
  huérfanos, invisible en los tests aislados. Ahora son autorados en
  `player.tscn` y `net_tests` comprueba que las ocho rutas de socket resuelven
  en las dos escenas.

  Queda para más adelante: el porteo a dos personas (atún, hombre al agua) y
  los barriles portables si el playtest los pide.

## Deuda declarada

- ~~La caña visible en el viewmodel mientras portás~~ — saldada en fase B:
  `_guardada()` la esconde clavada o con las manos cargadas. La pose de
  PORTEO del cuerpo (hoy caminás con los brazos de locomoción aunque
  abraces un atún) sigue pendiente; ANIMACION.md deja el hueco.
- La bodega de fase A es UNA celda en `HoldAft`; el doble servicio
  bodega=celdas de inundación (DISENO, slice) llega con el achique.
- La radio es muda: su estática y sus chasquidos van por la política
  ElevenLabs (regla 10), pendientes de generar y hornear. Hoy es un rol-
  objeto físico sin voz — el enlace cubierta↔máquinas de verdad llega con
  la voz por proximidad (F5).
- El bichero y la caja aún no ejercen su oficio (enganchar / taponar):
  entran con rescates y achique. Hoy son peso, compromiso de manos y
  comedia — que ya es la mitad de su papel.
