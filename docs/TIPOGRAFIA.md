# Tipografía — Faena costera

La tipografía del juego habla como un **pesquero de trabajo**: útil, robusta y
humana. No dibuja olas dentro de las letras ni usa cuerda, piratas o desgaste
falso. El mar ya pone el espectáculo; el texto tiene que seguir siendo legible
cuando la cámara, la espuma y la cubierta se están moviendo.

Esta es una dirección operativa para la UI y la identidad futura. **No cierra el
nombre ni el wordmark**: `Proyecto Agua` sigue siendo un título provisional.

## Las dos voces

| Voz | Fuente | Uso | Configuración |
|---|---|---|---|
| **Faena / impacto** | Anybody Variable | Imperativos, resultados, actos, niveles y título futuro | HUD: `wdth 92`, `wght 700`; marca: `wdth 118`, `wght 700` |
| **Información** | Atkinson Hyperlegible | Teclas, números, unidades, ayuda y texto sostenido | Regular y Bold nativas |

Noto Sans Symbols funciona solo como reserva para flechas y signos. Evita que
`←` y `→` cambien entre sistemas operativos sin sumar una tercera voz visible.

`GameTypography` es la única fábrica de variantes. Ninguna pantalla fija pesos
o anchos por su cuenta: así `¡RECOGE!`, `MURO` y el título pertenecen a la misma
familia sin tener las mismas métricas.

## Reglas de uso

- Mayúsculas para verbos urgentes, actos y nombres propios del mar:
  `¡RECOGE!`, `IMPACTO`, `MURO`, `COLOSO`, `LEVIATÁN`.
- Frase normal para explicaciones y consecuencias: `Se escapó...`, ayuda,
  bitácora y menús.
- El HUD urgente usa la variante condensada fija. **No se anima el ancho con la
  furia**: mover las métricas mientras se lee sería feedback decorativo y ruido.
- La variante ancha queda reservada para título, transiciones de acto y piezas
  promocionales. No debe invadir párrafos ni datos.
- Se mantienen contorno oscuro y sombra corta sobre el mundo 3D. La fuente no
  reemplaza el contraste que exige un fondo que cambia entre espuma y noche.
- Cobertura mínima: español completo, `¡¿`, punto medio, raya, flechas, corchetes,
  porcentaje, unidades y números. `tests/typography_tests.tscn` protege ese
  contrato.

## Superficies actuales

- `FishingHud`: Faena para picada, instrucciones y resultados; Atkinson Bold
  para teclas y flechas.
- Señal `!` sobre la boya: Faena, porque tiene que reconocerse a 20 m.
- `MenuPrincipal` (`docs/MENU.md`): es la primera aplicación de la **variante
  ancha**, y por ahora la única: el título de la portada, en mayúsculas, leído
  de `application/config/name` para que no se quede un nombre viejo colgado
  cuando se cierre el definitivo. Los botones usan la Faena condensada pero en
  **frase normal** —los menús van en frase normal aunque la voz sea la de
  impacto—, y toda la información (ayuda, teclas, aparatos de audio, avisos) va
  en Atkinson. Contorno y sombra en todo, más un velo en degradado: el fondo es
  el mar de verdad y cambia de espuma a sombra dentro de la misma ola.
- HUD de debug del océano: conserva por ahora la fuente técnica de Godot. No es
  UI final y sus columnas dependen de espacios manuales; forzarlo a la voz de
  marca empeoraría la herramienta.

## Paleta tipografica

- Espuma/crema: lectura principal.
- Latón/amarillo: aviso y oportunidad.
- Rojo antifouling/coral: rotura e impacto.
- Verde claro: ventana correcta y captura.
- Azul petróleo casi negro: contorno y sombra.

El color expresa estado; la forma de las letras expresa identidad. Nunca se usa
solo color para una instrucción que decide una captura.

## Licencias y exportación

Los tres archivos `OFL.txt` quedan junto a sus fuentes dentro del repositorio.
El proyecto todavía no tiene `export_presets.cfg`; la primera build distribuible
debe copiar esas licencias junto al ejecutable o incluir explícitamente
`assets/fonts/**/OFL.txt` en cada preset. No se considera publicable una build que
no entregue esos avisos en formato legible.
