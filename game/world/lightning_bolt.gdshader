shader_type spatial;

// El rayo visible (docs/CLIMA.md §2.2). Un quad con la silueta del rayo
// horneada en textura, recortada con step().
//
// step() y NO smoothstep, y blend_mix y NO blend_add: un rayo aditivo es un
// glow, y este proyecto pinta ilustracion plana — la espuma del mar ya tiene
// borde duro y el rayo tiene que pertenecer al mismo mundo. El "brillo" lo da
// el destello global (lightning01 promocionando bandas), no un halo local.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D bolt_tex : source_color, filter_linear_mipmap;
uniform float threshold : hint_range(0.0, 1.0) = 0.20;
// El rayo se REVELA de arriba abajo en ~100 ms: baja del cielo, no aparece
// entero. UV.y = 0 es arriba en un QuadMesh.
uniform float y_progress : hint_range(0.0, 1.0) = 1.0;
uniform vec3 bolt_color : source_color = vec3(0.94, 0.96, 1.0);
// Vida del trazo en ESCALONES, no en fundido continuo: el afterglow de un cel
// de anime salta de blanco pleno a banda clara y desaparece.
uniform float fade_step : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float v = texture(bolt_tex, UV).r;
	float core = step(threshold, v);
	float reveal = step(UV.y, y_progress);
	ALBEDO = bolt_color;
	ALPHA = core * reveal * fade_step;
}
