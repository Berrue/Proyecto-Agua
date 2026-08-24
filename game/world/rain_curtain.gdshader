shader_type spatial;

// Cortina de lluvia lejana (docs/CLIMA.md §1.1): la capa que hace legible la
// tormenta a media distancia, donde las gotas sueltas de RainParticles3D ya no
// llegan. Tecnica canonica (Remember Me / ToyShop): un cilindro pegado a la
// camara con trazos de agua en scroll — geometria barata, cero particulas.
//
// ⚠️ NO usar ruido de valor con celdas grandes aqui. La primera version
// muestreaba ruido a ~46 celdas por vuelta: a 45 m de radio eso son celdas de
// 6 m, o sea ~200 px en pantalla, y cuantizadas con step() se leian como
// MANCHONES de vapor, no como lluvia (feedback del playtest). La lluvia son
// TRAZOS FINOS: se dibujan como tales, columna a columna.
//
// cull_front: se ve desde dentro. depth_draw_never: transparente puro.
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

// Los escribe RainCurtain3D cada frame desde Ocean — jamas TIME (reloj local,
// regla de oro del repo).
uniform float curtain_time = 0.0;
uniform float rain01 : hint_range(0.0, 1.0) = 0.0;
// Brillo acoplado a la luz ambiente, como las gotas: de noche se apaga con la
// escena en vez de flotar gris.
uniform vec3 tint : source_color = vec3(0.75, 0.79, 0.84);
uniform float base_alpha : hint_range(0.0, 0.5) = 0.10;
// Trazos por vuelta completa. Con ~60 columnas visibles en un FOV de 62 grados
// cada trazo cae en ~7 px de ancho: fino, sin aliasear.
uniform float columns = 340.0;
// Ciclos por metro de altura. 0.045 = un trazo cada 22 m, del que ~7 m van a
// opacidad plena: a 45 m de distancia son ~200 px de alto. Los valores altos
// (0.16 de la primera pasada) daban trazos de 23 px que leian como LADRILLOS
// flotando, no como agua cayendo.
uniform float dashes_per_meter = 0.028;
// Semialtura del cilindro de ESTA capa: la mascara vertical se expresa en
// fraccion de altura, asi cada capa puede tener su tamaño sin recalibrar nada.
uniform float half_height = 42.0;
// Velocidad angular relativa. Las capas lejanas se mueven MAS LENTO: es el
// parallax lo que rompe la lectura de "cilindro" (Remember Me usaba 4 capas).
uniform float speed_scale = 1.0;
// Semilla de la capa: sin esto las dos capas comparten patron y se delatan.
uniform float layer_seed = 0.0;

varying vec2 v_uv;
// Altura LOCAL en metros. La caida se deriva de aqui y no de UV.y: asi "abajo"
// es abajo sin depender de como oriente las UV el CylinderMesh.
varying float v_local_y;

float cort_hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	v_uv = UV;
	v_local_y = VERTEX.y;
}

void fragment() {
	float col = floor(v_uv.x * columns);
	float phase = cort_hash(vec2(col, 3.7 + layer_seed));
	float speed = (0.75 + 0.55 * cort_hash(vec2(col, 11.3 + layer_seed))) * speed_scale;
	float pick = cort_hash(vec2(col, 5.1 + layer_seed));

	// Trazo fino centrado en su columna, con los bordes suaves (mismo criterio
	// que la textura de las gotas: la lluvia nunca tiene borde duro).
	float xin = fract(v_uv.x * columns);
	float line = 1.0 - smoothstep(0.05, 0.28, abs(xin - 0.5));

	// CAE. El signo importa y es facil de invertir sin darse cuenta: para un
	// trazo fijo (fract(py) constante) despejando queda y = (c - t*v)/k, o sea
	// que y DECRECE con el tiempo. Con el signo contrario en v_local_y la
	// cortina sube — se detecto en playtest y se verifico midiendo el
	// desplazamiento entre dos frames, no a ojo.
	float py = v_local_y * dashes_per_meter + curtain_time * speed + phase * 13.0;
	float dash = fract(py);
	// Trazo LARGO con cabeza y cola desvanecidas: mas cerca de un velo que de
	// una gota, que es lo que la distancia convierte a la lluvia.
	float streak = smoothstep(0.0, 0.05, dash) * (1.0 - smoothstep(0.34, 0.62, dash));

	// Cuantas columnas llueven: la intensidad abre columnas, no las engorda.
	float active = step(pick, rain01 * 0.85);

	// Vive en la franja del horizonte y muere hacia el cenit: el velo lejano se
	// lee contra el mar y el horizonte, no colgado del cielo alto. En fraccion
	// de semialtura para que valga en cualquier capa.
	float ny = v_local_y / half_height;
	float vmask = smoothstep(-1.0, -0.71, ny) * (1.0 - smoothstep(-0.05, 0.62, ny));

	// Atenuacion radial en PANTALLA (presupuesto anti-mareo, CLIMA §1.5): la
	// cortina vive en el centro de la vision; la periferia es de la viñeta.
	float r = length(SCREEN_UV - vec2(0.5)) * 2.0;
	float radial = 1.0 - smoothstep(0.72, 1.15, r);

	ALBEDO = tint;
	ALPHA = line * streak * active * vmask * radial * base_alpha * rain01;
}
