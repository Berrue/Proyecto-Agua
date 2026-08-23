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
// Distancia a la que se deja de facetar. Cerca queremos facetas legibles; lejos,
// facetar solo produce ruido de alta frecuencia que ademas aliasea.
uniform float facet_distance : hint_range(0.0, 400.0) = 120.0;
uniform float band_low : hint_range(-1.0, 1.0) = 0.02;
uniform float band_high : hint_range(-1.0, 1.0) = 0.42;
uniform float ambient_level : hint_range(0.0, 1.0) = 0.34;

group_uniforms SeaState;
// Lo unico que Ocean escribe aqui es `fury01`. Los rangos siguen siendo del
// artista, que es lo que permite tocar el aspecto sin tocar codigo.
uniform float fury01 : hint_range(0.0, 1.0) = 0.3;
uniform float detail_calm : hint_range(0.0, 3.0) = 0.25;
uniform float detail_storm : hint_range(0.0, 3.0) = 1.35;
// Lo escribe Ocean a partir del Hs actual, para que las bandas de color
// sigan comunicando altura tanto con olas de 20 cm como de 20 m.
uniform float height_scale = 0.24;

group_uniforms Foam;
// J < foam_bias marca rotura. Subirlo con la furia hace que el mar se llene de
// crestas blancas sin tocar nada mas.
uniform float foam_bias_calm : hint_range(0.0, 2.0) = 0.06;
uniform float foam_bias_storm : hint_range(0.0, 2.0) = 0.52;
uniform float foam_softness : hint_range(0.001, 0.5) = 0.14;

varying vec3 v_world;
varying vec3 v_world_normal;
varying float v_jacobian;

void vertex() {
	// La malla del oceano solo se traslada, nunca rota ni escala (lo garantiza
	// ocean_surface.gd), asi que basta sumar la traslacion para pasar a mundo.
	vec2 world_xz = VERTEX.xz + MODEL_MATRIX[3].xz;

	vec3 d = ocean_displacement(world_xz, ocean_time);
	VERTEX += d;

	// La transformada es solo traslacion, asi que una direccion en espacio de
	// modelo y en espacio de mundo son la misma.
	v_world_normal = ocean_normal(world_xz, ocean_time);
	NORMAL = v_world_normal;

	v_world = vec3(world_xz.x + d.x, d.y, world_xz.y + d.z);
	v_jacobian = ocean_jacobian(world_xz, ocean_time);
}

void fragment() {
	// Facetado: convierte una superficie continua en facetas legibles sin
	// prefacetar nada, que es imprescindible porque la malla se genera en
	// runtime. Se mezcla hacia la normal suave con la distancia para que el
	// horizonte no hierva.
	// Todo el trabajo de normales se hace en MUNDO y se pasa a vista al final.
	vec3 flat_world = normalize(cross(dFdx(v_world), dFdy(v_world)));
	float dist = length(VERTEX);
	float facet_mix = 1.0 - smoothstep(facet_distance * 0.5, facet_distance, dist);
	vec3 n_world = normalize(mix(normalize(v_world_normal), flat_world, facet_mix));

	// Detalle de alta frecuencia: perturba la normal, no la geometria. Se
	// desvanece con la distancia porque de cerca es textura y de lejos solo
	// seria ruido que aliasea.
	float detail_amount = mix(detail_calm, detail_storm, fury01)
		* (1.0 - smoothstep(60.0, 240.0, dist));
	vec2 dgrad = ocean_detail_gradient(v_world.xz, ocean_time) * detail_amount;
	n_world = normalize(n_world + vec3(-dgrad.x, 0.0, -dgrad.y));

	NORMAL = (VIEW_MATRIX * vec4(n_world, 0.0)).xyz;

	// Color por altura, en bandas planas y no en gradiente: es la diferencia
	// entre "tengo un shader toon" y "tengo direccion de arte".
	float h = clamp(v_world.y * height_scale + 0.5, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, smoothstep(0.35, 0.55, h));
	col = mix(col, crest_color, smoothstep(0.62, 0.78, h));

	// Espuma por Jacobiano. J < 0 significa que la cresta se pliega sobre si
	// misma, o sea que la ola ROMPE. `Ocean.get_breaking()` evalua exactamente
	// este mismo numero en CPU para disparar el revolcon y el daño: lo que el
	// jugador ve blanco es literalmente donde le va a pegar el mar.
	float foam_bias = mix(foam_bias_calm, foam_bias_storm, fury01);
	float foam = 1.0 - smoothstep(foam_bias - foam_softness, foam_bias + foam_softness, v_jacobian);
	// Cuantizada a dos valores con borde duro. Nada de alpha suave: el lenguaje
	// visual es de ilustracion plana, no de fotografia.
	foam = step(0.5, foam) * 0.75 + step(0.85, foam) * 0.25;
	col = mix(col, foam_color, foam);

	ALBEDO = col;
	ROUGHNESS = 1.0; // constante y alta: un roughness variable hace hervir las bandas
	METALLIC = 0.0;
}

void light() {
	// Rampa de luz cuantizada. `smoothstep` con ancho proporcional a `fwidth`
	// en vez de `step` puro: es LA mitigacion del riesgo tecnico numero 1 de
	// esta estetica, porque el step duro sobre una superficie en movimiento
	// hierve y parpadea.
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
