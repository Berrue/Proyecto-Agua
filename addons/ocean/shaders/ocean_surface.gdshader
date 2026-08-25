shader_type spatial;

// Agua OPACA a proposito. Nada de `hint_screen_texture`: forzar una copia del
// back buffer sobre una superficie que cubre media pantalla es el coste
// dominante de cualquier oceano en Forward+, y encima los transparentes se
// ordenan por la posicion del nodo y no por vertice, lo que con mar + spray +
// props flotantes es un desastre garantizado.
//
// `cull_disabled` para poder ver la superficie desde debajo del agua.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_disabled;

#include "res://addons/ocean/shaders/ocean_waves.gdshaderinc"

group_uniforms Color;
uniform vec3 deep_color : source_color = vec3(0.043, 0.129, 0.216);
uniform vec3 shallow_color : source_color = vec3(0.102, 0.325, 0.404);
uniform vec3 crest_color : source_color = vec3(0.267, 0.494, 0.541);
uniform vec3 foam_color : source_color = vec3(0.902, 0.945, 0.949);

group_uniforms Shading;
// APAGADO POR DEFECTO (0.0), y el motivo esta medido, no supuesto.
//
// La faceta se calcula con dFdx/dFdy, o sea que es constante POR TRIANGULO. Con
// celdas de ~2.3 m vistas desde cubierta, los triangulos son demasiado pequeños
// para leerse como estilo y lo que produce es muare. Se aislo apagando esto: el
// muare desaparece por completo.
//
// El arreglo correcto (fase de look) es desacoplar el tamaño de FACETA del de la
// CELDA: evaluar la normal en una posicion cuantizada a N metros, para que la
// faceta sea un parametro de arte y no un efecto secundario de la teselacion.
// Cuesta una evaluacion de normal por pixel, asi que se decide cuando exista el
// clipmap (que va a cambiar el tamaño de celda de todas formas).
uniform float facet_distance : hint_range(0.0, 400.0) = 0.0;
uniform float band_low : hint_range(-1.0, 1.0) = 0.02;
uniform float band_high : hint_range(-1.0, 1.0) = 0.42;
uniform float ambient_level : hint_range(0.0, 1.0) = 0.26;

group_uniforms Clima;
// `Ocean.apply_frame_to_material()` YA escribia estos cada frame — llevaban
// meses cayendo al vacio porque el shader no los declaraba, asi que la lluvia
// no tocaba el agua y nadie veia un error. Declararlos es literalmente todo lo
// que faltaba: el cableado del otro lado ya estaba hecho y corriendo.
uniform float rain01 : hint_range(0.0, 1.0) = 0.0;
uniform float gust01 : hint_range(0.0, 1.0) = 0.5;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform vec2 wind_drift = vec2(0.0, 0.0);

// El destello del rayo, en unidades de BANDA de la rampa cuantizada, no en
// brillo. Lo escribe LightningDirector como uniform GLOBAL, asi que el cielo
// (sky.gdshader) y el mar leen exactamente el mismo numero en el mismo frame.
// Sin esto el cielo relampagueaba y el mar —media pantalla— no se enteraba.
global uniform float lightning01;

// --- Tanda 2: las dos cosas que son GUSTO, no fisica ------------------------
// Las dos entran en 0.0 a proposito. El moteado de "chispazos" de la fase A
// murio en playtest por leerse como «puntos sin sentido», y estas dos son de
// la misma familia visual: manchas de ruido sobre agua. Se entregan apagadas
// con capturas al lado para que la decision se tome MIRANDO, con la misma
// evidencia con la que se mato el moteado. Subirlas a 1.0 es todo lo que hace
// falta si convencen.

// CAT'S PAWS: las manchas oscuras que corren sobre el agua cuando pega una
// racha. Son reales y son la primera señal de viento que se ve en el mar —
// pero solo se leen con mar chico: en un temporal la superficie entera esta
// rota y no hay nada que manchar.
//
// SE QUEDA EN 0: descartada mirando capturas (2026-08-24). A tope movia el
// 6.8 % de los pixeles con una diferencia media de 1 sobre 255, o sea que hay
// que buscarla para verla. El codigo se deja porque en cero no cuesta nada y
// la idea es buena; lo que no funciona es esta implementacion.
uniform float paw_amount : hint_range(0.0, 1.0) = 0.0;
// ESTRIAS: las lineas de espuma que el viento estira en la direccion en que
// sopla (Langmuir). Aparecen de furia 5-6 para arriba y son lo que dice
// «esto ya no es oleaje, es temporal».
// ENCENDIDA en 0.15 (decision del diseñador 2026-08-24, mirando capturas).
// Es MUCHO mas bajo que el 0.3 que se probo: a 0.3 ya eran cintas anchas
// cruzando la pantalla y a 1.0 el mar quedaba medio blanco. A 0.15 son cuatro
// tiras finas que solo se leen en temporal, que es justo lo que se buscaba.
uniform float streak_amount : hint_range(0.0, 1.0) = 0.15;


// Ruido propio del clima. Vive AQUI y no en `ocean_waves.gdshaderinc` a
// proposito: el include es el espejo EXACTO de la CPU (regla 3), y meterle
// funciones que la CPU no tiene abriria la puerta a que alguien las use en el
// desplazamiento y rompa la paridad sin enterarse. Esto es solo pintura.
float clima_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float clima_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = clima_hash(i);
	float b = clima_hash(i + vec2(1.0, 0.0));
	float c = clima_hash(i + vec2(0.0, 1.0));
	float d = clima_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

group_uniforms SeaState;
// Lo unico que Ocean escribe aqui es `fury01` y `height_scale`. Los rangos
// siguen siendo del artista, que es lo que permite tocar el aspecto sin tocar
// codigo ni recompilar nada.
uniform float fury01 : hint_range(0.0, 1.0) = 0.3;
uniform float detail_calm : hint_range(0.0, 3.0) = 0.25;
uniform float detail_storm : hint_range(0.0, 3.0) = 1.1;
// Lo escribe Ocean a partir del Hs actual, para que las bandas de color sigan
// comunicando altura tanto con olas de 20 cm como de 20 m.
uniform float height_scale = 0.24;

group_uniforms Foam;
// J < foam_bias marca rotura. Subirlo con la furia llena el mar de crestas
// blancas sin tocar nada mas.
uniform float foam_bias_calm : hint_range(0.0, 2.0) = 0.06;
uniform float foam_bias_storm : hint_range(0.0, 2.0) = 0.52;
uniform float foam_softness : hint_range(0.001, 0.5) = 0.14;
// Cuanto puede el patron abrir huecos en la espuma. A 0 vuelve a ser una sabana.
uniform float foam_break_up : hint_range(0.0, 1.0) = 0.9;

varying vec3 v_world;
varying vec3 v_world_normal;
varying float v_jacobian;
varying float v_event_height;

void vertex() {
	// La malla del oceano solo se traslada, nunca rota ni escala (lo garantiza
	// ocean_surface.gd), asi que basta sumar la traslacion para pasar a mundo.
	vec2 world_xz = VERTEX.xz + MODEL_MATRIX[3].xz;

	vec3 d = ocean_displacement(world_xz, ocean_time);
	// La capa de eventos es puramente VERTICAL: no desplaza en horizontal, asi
	// que se suma sin tocar la inversion de Gerstner.
	v_event_height = ocean_event_height(world_xz, ocean_time);
	d.y += v_event_height;
	VERTEX += d;

	// La transformada es solo traslacion, asi que una direccion en espacio de
	// modelo y en espacio de mundo son la misma.
	vec3 wn = ocean_normal(world_xz, ocean_time);
	// Inclinar la normal con la pendiente del frente del tsunami. Sin esto, la
	// pared de agua se ilumina como si fuera plana y pierde todo el volumen.
	float ev_slope = ocean_event_slope(world_xz, ocean_time);
	vec2 ev_dir = event_a[0].zw;
	wn = normalize(wn - vec3(ev_dir.x, 0.0, ev_dir.y) * ev_slope);
	v_world_normal = wn;
	NORMAL = wn;

	v_world = vec3(world_xz.x + d.x, d.y, world_xz.y + d.z);
	// Un solo Jacobiano para las dos capas: el frente del tsunami cuenta como
	// rotura por su pendiente, igual que una cresta se pliega por la suya.
	v_jacobian = ocean_jacobian(world_xz, ocean_time)
		- ocean_event_break_penalty(world_xz, ocean_time);
}

void fragment() {
	float dist = length(VERTEX);

	// --- La espuma va PRIMERO: decide cuanto detalle se aplica despues --------
	//
	// J < 0 significa que la cresta se pliega sobre si misma, o sea que la ola
	// ROMPE. `Ocean.get_breaking()` evalua exactamente este mismo numero en CPU
	// para disparar el revolcon y el daño: lo que el jugador ve blanco es
	// literalmente donde le va a pegar el mar.
	float foam_bias = mix(foam_bias_calm, foam_bias_storm, fury01);
	float foam_raw = 1.0 - smoothstep(foam_bias - foam_softness, foam_bias + foam_softness, v_jacobian);

	// El patron rompe la espuma en placas. Sin el, en cuanto una zona entra en
	// rotura se pinta de blanco plano y el muro del tsunami deja de leerse como
	// agua: parece nieve.
	float pattern = ocean_foam_pattern(v_world.xz, ocean_time);
	float foam = foam_raw * mix(1.0, 0.2 + 1.5 * pattern, foam_break_up);

	// ESTRIAS DE VIENTO. El dominio se estira 16:1 A LO LARGO del viento, asi
	// que el mismo ruido de siempre sale en tiras largas en vez de en manchas.
	// Van ANTES de la cuantizacion —con un `max`, no sumando— para que salgan
	// del mismo borde duro que el resto de la espuma: sumarlas despues daria
	// tiras de alpha suave sobre un mar de bordes planos, y cantaria.
	if (streak_amount > 0.001) {
		vec2 a_favor = wind_dir;
		vec2 de_traves = vec2(-wind_dir.y, wind_dir.x);
		// Bandas ESTRECHAS (0.9 m de ancho, 60 de largo). Con 2.6 m salian
		// cintas del ancho de una calle que cruzaban la pantalla entera.
		vec2 s_uv = vec2(dot(v_world.xz, a_favor) / 60.0,
			dot(v_world.xz, de_traves) / 1.6);
		float sn = clima_noise(s_uv - vec2(ocean_time * 0.05, 0.0));
		// ^3 afila: deja pocas tiras marcadas en vez de un rayado parejo, que
		// es como se ven de verdad (Langmuir hace calles, no textura).
		float sraw = pow(sn, 3.0) * smoothstep(0.5, 0.85, fury01);
		// El nivel mueve el UMBRAL, o sea CUANTA superficie se raya — no cuan
		// blanca queda. Escalando la magnitud, como estaba antes, el efecto era
		// todo-o-nada: por debajo de ~0.39 no cruzaba el corte duro de la
		// espuma y no se veia NADA (medido: 0.0 % de pixeles), y por encima se
		// pintaban autopistas blancas. Un knob con dos posiciones no es un knob.
		float umbral = mix(0.60, 0.03, streak_amount);
		// Y se pintan en la banda BAJA de espuma (0.75 -> 0.7 tras cuantizar),
		// no en la alta: una estria es agua rayada, no una cresta rompiendo.
		// Se PROBO atarlas a `foam_raw` (la idea correcta en teoria: una estria
		// es espuma estirada, sin espuma no hay estria) y MATA el efecto por
		// completo — medido: 0.0 % de pixeles con dos umbrales distintos.
		// Motivo: a furia 8 `foam_bias` vale ~0.43 y el jacobiano ronda 1.0-1.2,
		// asi que `foam_raw` es cero salvo en las crestas que rompen de verdad,
		// que son cuatro pixeles. La puerta correcta seria la PENDIENTE de la
		// ola, no su rotura; queda anotado por si alguien lo retoma.
		if (sraw > umbral) {
			foam = max(foam, 0.75);
		}
	}

	// Cuantizada con borde duro. Nada de alpha suave: el lenguaje visual es de
	// ilustracion plana, no de fotografia.
	foam = step(0.62, foam) * 0.7 + step(1.02, foam) * 0.3;

	// CAT'S PAWS. La mancha viaja con `wind_drift`, que es el avance acumulado
	// del patron sobre el agua que Ocean ya integra y ya empuja aqui: por eso
	// las manchas CORREN en la direccion del viento en vez de quedarse
	// clavadas al mundo.
	//
	// Doble puerta de furia: aparecen con la primera brisa (furia ~0.5) y se
	// apagan pasada la 5-6, porque con el mar ya roto no hay superficie lisa
	// que rizar y quedarian como suciedad sobre la espuma.
	float paw = 0.0;
	if (paw_amount > 0.001) {
		float f10 = fury01 * 10.0;
		float puerta = smoothstep(0.4, 1.2, f10) * (1.0 - smoothstep(4.5, 6.0, f10));
		vec2 paw_uv = (v_world.xz - wind_drift) / 26.0;
		// Mascara ANCHA: con 0.60-0.78 solo se pintaba ~1 de cada 4 celdas y el
		// efecto a tope movia el 2.6 % de los pixeles, o sea nada.
		paw = smoothstep(0.48, 0.70, clima_noise(paw_uv))
			* puerta * gust01 * paw_amount;
	}

	// --- Normales ------------------------------------------------------------
	vec3 flat_world = normalize(cross(dFdx(v_world), dFdy(v_world)));
	float facet_mix = 1.0 - smoothstep(facet_distance * 0.5, facet_distance, dist);
	vec3 n_world = normalize(mix(normalize(v_world_normal), flat_world, facet_mix));

	// Detalle de alta frecuencia: perturba la normal, nunca la geometria.
	//
	// Se atenua por HUELLA EN PANTALLA, no por distancia. La distancia sola no
	// vale: a angulo rasante un pixel cerca de la camara puede cubrir varios
	// metros de agua, y ahi una ondulacion de 2.6 m ya no se puede representar y
	// solo produce muare. `fwidth` del mundo da directamente cuantos metros
	// abarca un pixel, que es el criterio correcto (el mismo razonamiento que un
	// mip level).
	float footprint = max(length(fwidth(v_world.xz)), 1e-4);
	float lod_fade = 1.0 - smoothstep(0.35, 1.4, footprint);
	// Y tambien se apaga BAJO LA ESPUMA: el agua rota es difusa, asi que
	// mantener ahi el relieve fino hace que la rampa cuantizada parpadee sobre
	// el blanco.
	// La lluvia APLANA el relieve fino. Millones de gotas picando la superficie
	// destruyen el rizado capilar que produce el centelleo: por eso un mar bajo
	// aguacero se lee mate y "pesado" aunque las olas grandes sigan iguales.
	float detail_amount = mix(detail_calm, detail_storm, fury01)
		* lod_fade
		* (1.0 - 0.85 * foam)
		* mix(1.0, 0.4, rain01)
		// La mancha ES rizado, asi que algo mas de relieve fino — pero POCO.
		// Con 1.8 (o sea x2.8) las normales se perturbaban tanto que el agua
		// saltaba a la banda de cresta y las manchas salian TURQUESA BRILLANTE:
		// exactamente lo contrario de una cat's paw, que es una sombra. El
		// efecto tiene que venir del color, no de romper el sombreado.
		* (1.0 + 0.45 * paw);
	vec2 dgrad = ocean_detail_gradient(v_world.xz, ocean_time) * detail_amount;
	n_world = normalize(n_world + vec3(-dgrad.x, 0.0, -dgrad.y));

	NORMAL = (VIEW_MATRIX * vec4(n_world, 0.0)).xyz;

	// --- Color ---------------------------------------------------------------
	// Bandas planas, no gradiente: es la diferencia entre "tengo un shader toon"
	// y "tengo direccion de arte".
	//
	// Se banda sobre el OLEAJE, restando la aportacion del tsunami. Si no, un
	// muro de 28 m contra un Hs de 9 satura la escala y el mar entero se pinta
	// del color de cresta: las bandas dejan de comunicar nada justo en el
	// momento en que mas falta hace leer el agua. El volumen del muro lo
	// comunican su silueta y su espuma, no el color.
	float h = clamp((v_world.y - v_event_height) * height_scale + 0.5, 0.0, 1.0);
	// EL DESTELLO DEL RAYO promociona la banda de COLOR, no la de luz.
	//
	// Empezo mal: bajando los umbrales de `light()`. Medido con un A/B del
	// mismo mar (`flash_off`/`flash_on` de capture_weather), eso movia el brillo
	// del agua un -0.5 %, o sea nada — porque bajar un umbral solo ilumina lo
	// que estaba POR DEBAJO, y de dia el mar mira hacia arriba con el sol
	// arriba: ya esta en la banda mas alta y no hay ninguna por encima.
	//
	// Aqui si funciona, y ademas es lo que «promocion de banda» queria decir:
	// el agua se pinta un escalon mas clara de su propia rampa (hacia cresta),
	// una sola vez por pixel, sin depender del angulo del sol ni de que haya
	// sol. Y sigue siendo un salto DISCRETO y contable, que es lo que hace
	// verificable el limite fotosensible (docs/CLIMA.md §2.5).
	h = clamp(h + clamp(lightning01, 0.0, 1.0) * 0.22, 0.0, 1.0);
	// Y la mancha OSCURECE: una superficie rizada devuelve menos luz al ojo,
	// que es exactamente por lo que en el mar se ven como sombras corriendo.
	h = clamp(h - 0.5 * paw, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, smoothstep(0.35, 0.55, h));
	col = mix(col, crest_color, smoothstep(0.62, 0.78, h));
	col = mix(col, foam_color, foam);

	ALBEDO = col;
	ROUGHNESS = 1.0; // constante y alta: un roughness variable hace hervir las bandas
	METALLIC = 0.0;
}

void light() {
	// Rampa de luz cuantizada. `smoothstep` con ancho proporcional a `fwidth` en
	// vez de `step` puro: es LA mitigacion del riesgo tecnico numero 1 de esta
	// estetica, porque el step duro sobre una superficie en movimiento hierve y
	// parpadea.
	float ndl = dot(NORMAL, LIGHT);
	float w = fwidth(ndl) * 1.5 + 0.005;

	// El destello tambien baja los umbrales de la rampa de luz. Esto SOLO hace
	// algo donde el agua esta a contraluz o de noche (superficies por debajo
	// del umbral); de dia con el sol alto no aporta nada, y por eso el trabajo
	// de verdad lo hace la promocion de la rampa de COLOR en `fragment()`.
	// Se mantiene porque es justo la cara nocturna del mismo efecto.
	float flash = clamp(lightning01, 0.0, 1.0);
	float lo = band_low - flash * 0.55;
	float hi = band_high - flash * 0.55;

	float b1 = smoothstep(lo - w, lo + w, ndl);
	float b2 = smoothstep(hi - w, hi + w, ndl);
	float ramp = ambient_level + 0.38 * b1 + 0.28 * b2;

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ramp;

	// Destello del sol estampado como blob duro, no como lobulo difuso.
	//
	// LA LLUVIA LO MATA, y es la señal numero uno de "esta lloviendo sobre el
	// mar" (docs/CLIMA.md §1.3): la superficie picada deja de ser un espejo, y
	// el reflejo del sol se deshace en mil trozos demasiado chicos para verse.
	// Se encoge el blob (umbral mas alto = menos angulo lo alcanza) Y se baja
	// su intensidad: solo bajar el brillo dejaria un parche gris del tamaño
	// del sol, que es peor que no tener nada.
	vec3 half_vec = normalize(LIGHT + VIEW);
	float ndh = dot(NORMAL, half_vec);
	float sw = fwidth(ndh) * 1.5 + 0.002;
	float umbral = mix(0.982, 0.994, rain01);
	float spec = smoothstep(umbral - sw, umbral + sw, ndh);
	SPECULAR_LIGHT += spec * LIGHT_COLOR * ATTENUATION * 0.6 * (1.0 - 0.7 * rain01);
}
