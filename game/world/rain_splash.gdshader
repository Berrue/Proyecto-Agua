shader_type spatial;

// Anillos de impacto de la lluvia sobre el mar (docs/CLIMA.md §1.2). Cada
// particula es un plano horizontal que se CLAVA en la superficie evaluando la
// misma suma Gerstner que dibuja el oceano — no una altura fija, que flotaria
// sobre las crestas y se hundiria en los valles.
//
// `world_vertex_coords`: VERTEX llega ya en espacio de mundo, asi que el
// desplazamiento del agua se suma directo sin transformar nada.
//
// Los uniforms de ola los empuja RainSplashes3D por la MISMA tuberia que el
// oceano (Ocean.apply_to_material): nunca dos listas de constantes.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, world_vertex_coords;

#include "res://addons/ocean/shaders/ocean_waves.gdshaderinc"

uniform vec3 foam_color : source_color = vec3(0.902, 0.945, 0.949);
// Radio interior/exterior del aro dentro del quad (0 = centro, 1 = borde).
uniform float ring_inner : hint_range(0.0, 1.0) = 0.66;
uniform float ring_outer : hint_range(0.0, 1.0) = 0.88;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;
// A partir de aqui el aro se apaga: mas lejos es sub-pixel y solo hierve.
uniform float fade_start = 14.0;
uniform float fade_end = 26.0;
// El aro se despega un pelo del agua. Sin esto la mitad que queda por debajo
// de la superficie la ocluye el propio mar y el anillo sale como MEDIA LUNA
// (depth_draw_never no escribe profundidad, pero si la comprueba).
uniform float surface_lift = 0.05;

varying float v_dist;

void vertex() {
	// CADA VERTICE va a su propio punto de agua (no el quad entero al de su
	// centro): asi el aro se CURVA con la ola en vez de atravesarla como una
	// tapa rigida. Es la misma convencion que la malla del oceano: posicion de
	// reposo + desplazamiento.
	vec2 rest_xz = VERTEX.xz;
	vec3 d = ocean_displacement(rest_xz, ocean_time);
	d.y += ocean_event_height(rest_xz, ocean_time) + surface_lift;
	VERTEX += d;
	v_dist = length((VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	// Aro de borde DURO: el lenguaje del proyecto es ilustracion plana, y la
	// espuma del oceano ya se cuantiza igual.
	float ring = step(ring_inner, r) * (1.0 - step(ring_outer, r));
	float fade = 1.0 - smoothstep(fade_start, fade_end, v_dist);

	ALBEDO = foam_color;
	// COLOR.a viene del degradado de vida de la particula: el aro nace, crece
	// (por la curva de escala) y se apaga.
	ALPHA = ring * fade * COLOR.a * max_alpha;
}
