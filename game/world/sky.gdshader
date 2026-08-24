shader_type sky;

// Cielo de "Proyecto Agua" (docs/CLIMA.md §3.6, fase C). Sustituye al
// ProceduralSkyMaterial por tres motivos concretos:
//
// 1. El procedural pinta UN DISCO POR CADA DirectionalLight3D de la escena, asi
//    que al añadir la luz dedicada al rayo aparecio un tercer "sol" difuso
//    flotando en el cielo (visto en playtest). Aqui los discos los dibujo yo, a
//    partir de direcciones EXPLICITAS que escribe DayNightCycle: añadir luces
//    al mundo no vuelve a ensuciar el cielo.
// 2. Necesitamos nubes que se cierren con la furia; el procedural no tiene.
// 3. El destello del rayo tiene que promocionar banda tambien arriba, con la
//    misma regla que el agua.
//
// use_half_res_pass: el fbm de nubes se evalua a 1/4 de pixeles. La
// cuantizacion por bandas esconde el reescalado, asi que sale gratis.
render_mode use_half_res_pass;

// --- Gradiente. MISMOS NOMBRES que ProceduralSkyMaterial a proposito: el
// perfil dia/noche (.tres) sigue siendo la fuente y no hubo que tocarlo.
group_uniforms Gradiente;
uniform vec3 sky_top_color : source_color = vec3(0.235, 0.318, 0.4);
uniform vec3 sky_horizon_color : source_color = vec3(0.545, 0.596, 0.62);
uniform vec3 ground_horizon_color : source_color = vec3(0.545, 0.596, 0.62);
uniform vec3 ground_bottom_color : source_color = vec3(0.157, 0.196, 0.239);
uniform float sky_curve : hint_range(0.05, 1.0) = 0.35;

// --- Astros: direccion explicita, no LIGHTn. El indice que Godot asigna a cada
// luz no esta garantizado, y con tres luces en escena adivinarlo es una bomba.
group_uniforms Astros;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float sun_visible : hint_range(0.0, 1.0) = 1.0;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_color : source_color = vec3(0.75, 0.82, 0.95);
uniform float moon_visible : hint_range(0.0, 1.0) = 0.0;
// Radio angular del disco, en coseno. Discos PEQUEÑOS y de borde duro: el
// procedural los daba de 24 grados y difusos, que es lo que se leia como
// "manchon" en vez de como astro.
uniform float disc_cos : hint_range(0.99, 0.9999) = 0.9985;

// --- Clima. Lo escribe DayNightCycle leyendo de Ocean (un solo dueño del
// material del cielo: dos escritores se pisarian como pasaba con la niebla).
group_uniforms Clima;
uniform float sky_time = 0.0;
uniform float fury01 : hint_range(0.0, 1.0) = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_speed = 0.0;
// Frente de tormenta en el horizonte: lo conectara el director dramatico
// (fase D). A 0 no dibuja nada.
uniform float front01 : hint_range(0.0, 1.0) = 0.0;
uniform vec2 front_dir = vec2(0.0, 1.0);

group_uniforms Nubes;
uniform float cloud_height = 900.0;
uniform float cloud_scale = 0.00055;
uniform vec3 cloud_lit : source_color = vec3(0.85, 0.87, 0.9);
uniform vec3 cloud_dark : source_color = vec3(0.42, 0.46, 0.53);
// Bandas del cielo. Mas finas que las del agua A PROPOSITO: el mar se cuantiza
// sobre la ILUMINACION de una superficie con normales, y ahi el escalon lee
// como estilo; el cielo es un gradiente casi plano estirado por media pantalla,
// y a 14 bandas los escalones salian como CONTORNOS de posterizacion. Con 26 y
// dither el paso queda por debajo del umbral de contorno pero el destello sigue
// subiendo escalones enteros.
uniform float bands : hint_range(4.0, 64.0) = 40.0;

global uniform float lightning01;


float sky_hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float sky_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(sky_hash(i), sky_hash(i + vec2(1.0, 0.0)), u.x),
		mix(sky_hash(i + vec2(0.0, 1.0)), sky_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float sky_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * sky_noise(p);
		p *= 2.03; // no 2.0 exacto: evita que las octavas se alineen en rejilla
		a *= 0.5;
	}
	return v;
}

vec3 base_gradient(vec3 dir) {
	float h = dir.y;
	vec3 col = h >= 0.0
		? mix(sky_horizon_color, sky_top_color, pow(clamp(h, 0.0, 1.0), sky_curve))
		: mix(ground_horizon_color, ground_bottom_color, pow(clamp(-h, 0.0, 1.0), sky_curve));
	// Paleta de tormenta: desaturar hacia la luminancia y oscurecer. ANTES de
	// cuantizar, para que el encapotado mueva bandas enteras.
	float cov = pow(fury01, 0.7);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// Encapotado: hacia gris PLOMIZO, no hacia gris claro. Con el gris claro el
	// temporal se leia como calima blanca en vez de como tormenta.
	return mix(col, vec3(lum) * 0.38, cov * 0.8);
}

// Proyeccion del rayo de vision a un plano de nubes a `cloud_height` metros.
// Cerca del horizonte la division explota, asi que el denominador se acota.
vec2 cloud_uv(vec3 dir, float scale) {
	return dir.xz / max(abs(dir.y), 0.055) * cloud_height * scale;
}

void sky() {
	float cov = pow(fury01, 0.7);
	vec2 drift = wind_dir * (wind_speed * sky_time * 0.00035);

	// Sin `return`: el procesador `sky()` de Godot no lo admite, asi que los
	// tres pases se encadenan con if/else.
	if (AT_CUBEMAP_PASS) {
		// El cubemap de radiancia alimenta luz ambiente y reflejos, y se
		// regenera cada frame porque el cielo cambia. Aqui va SOLO baja
		// frecuencia: con el fbm fino dentro, el scroll de las nubes hace
		// hervir el ambiente de toda la escena.
		COLOR = base_gradient(EYEDIR) * (1.0 + lightning01 * 0.8);
	} else if (AT_HALF_RES_PASS) {
		// Dos capas del mismo ruido a escalas y velocidades distintas: nubes
		// que "evolucionan" sin animar nada (el truco de Wind Waker).
		vec2 uv1 = cloud_uv(EYEDIR, cloud_scale) + drift;
		vec2 uv2 = cloud_uv(EYEDIR, cloud_scale * 1.7) + drift * 0.6 + vec2(17.3, 5.1);
		float n = sky_fbm(uv1) * 0.65 + sky_fbm(uv2) * 0.35;

		// Al cerrarse el cielo los bordes tambien se ENDURECEN: mas agresivo,
		// mas grafico, menos algodon.
		float cutoff = mix(0.62, 0.12, cov);
		float fuzz = mix(0.10, 0.03, cov);
		float mask = smoothstep(cutoff, cutoff + fuzz, n);
		// Se desvanecen hacia el horizonte: si no, la proyeccion al plano las
		// estira hasta el infinito y se ve la costura.
		// La proyeccion al plano de nubes se dispara cerca del horizonte (el
		// denominador tiende a cero), asi que ahi el ruido aliasea y sale como
		// churretes oscuros. Se apaga antes de llegar.
		mask *= smoothstep(0.10, 0.38, EYEDIR.y);

		// Dos tonos por nube, no un degradado.
		vec3 c = mix(cloud_dark, cloud_lit, smoothstep(cutoff, cutoff + fuzz * 3.0, n));
		// Sheet lightning: las nubes se encienden POR DENTRO, y las densas mas.
		c += lightning01 * mask * 0.9;
		COLOR = c;
		ALPHA = mask;
	} else {
		vec3 col = base_gradient(EYEDIR);
		vec3 dir = normalize(EYEDIR);

		// Astros: disco de borde duro. ANTES que las nubes, para que estas los
		// tapen — es lo que hace creible el encapotado.
		col = mix(col, sun_color, step(disc_cos, dot(dir, normalize(sun_dir))) * sun_visible);
		col = mix(col, moon_color, step(disc_cos, dot(dir, normalize(moon_dir))) * moon_visible);

		// Nubes del pase de media resolucion.
		col = mix(col, HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);

		// Frente de tormenta: banda direccional pegada al horizonte que CRECE
		// al acercarse. Telegrafia espacial al estilo Sea of Thieves, sin
		// geometria. A front01 = 0 no dibuja nada.
		if (front01 > 0.001) {
			vec2 hdir = normalize(EYEDIR.xz + vec2(1e-5));
			float arc = mix(0.97, -0.2, front01);
			float band = smoothstep(arc, 1.0, dot(hdir, normalize(front_dir)));
			float top = mix(0.02, 0.34, front01);
			// La silueta sale de recortar un fbm de MUY baja frecuencia: torres
			// de cumulonimbo en vez de un degradado amorfo.
			float towers = sky_fbm(hdir * 2.3) * 0.35;
			float wall = band * (1.0 - smoothstep(top * (0.6 + towers), top * 1.6, EYEDIR.y));
			col = mix(col, cloud_dark * 0.55, clamp(wall, 0.0, 1.0) * front01);
		}

		// El destello suma ANTES de cuantizar: sube escalones enteros de la
		// escalera de bandas, igual que en el agua. Nada de bloom.
		col += lightning01 * 0.55;

		// Cuantizacion final con DITHER: cuantizar a secas un gradiente suave
		// dibuja contornos visibles (se vio en captura). El ruido de medio
		// escalon los rompe y deja el paso como textura, no como linea.
		// Medio escalon seria el dither "correcto", pero a ojo deja GRANO: un
		// cuarto rompe el contorno igual y no se ve.
		float dither = (sky_hash(SCREEN_UV * 1237.0) - 0.5) * 0.5 / bands;
		COLOR = floor((col + dither) * bands) / bands;
	}
}
