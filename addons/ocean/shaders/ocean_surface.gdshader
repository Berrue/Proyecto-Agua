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
	// Cuantizada con borde duro. Nada de alpha suave: el lenguaje visual es de
	// ilustracion plana, no de fotografia.
	foam = step(0.62, foam) * 0.7 + step(1.02, foam) * 0.3;

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
	float detail_amount = mix(detail_calm, detail_storm, fury01)
		* lod_fade
		* (1.0 - 0.85 * foam);
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

	float b1 = smoothstep(band_low - w, band_low + w, ndl);
	float b2 = smoothstep(band_high - w, band_high + w, ndl);
	float ramp = ambient_level + 0.38 * b1 + 0.28 * b2;

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ramp;

	// Destello del sol estampado como blob duro, no como lobulo difuso.
	vec3 half_vec = normalize(LIGHT + VIEW);
	float ndh = dot(NORMAL, half_vec);
	float sw = fwidth(ndh) * 1.5 + 0.002;
	float spec = smoothstep(0.982 - sw, 0.982 + sw, ndh);
	SPECULAR_LIGHT += spec * LIGHT_COLOR * ATTENUATION * 0.6;
}
