// =============================================================================
//  ocean_waves.gdshaderinc  —  LA FORMULA COMPARTIDA
// =============================================================================
//  ⚠️ CONTRATO CRITICO DEL PROYECTO ⚠️
//
//  Este archivo y `addons/ocean/wave_proxy.gd` implementan EXACTAMENTE la misma
//  matematica. Si divergen, los objetos flotan por encima o por debajo del agua
//  que se ve en pantalla, y el fallo es COMPLETAMENTE SILENCIOSO: cada pantalla
//  se ve perfecta por separado.
//
//  Si tocas una formula aqui, tocala tambien alli. `tests/test_wave_parity.gd`
//  lo verifica y hace fallar el build.
//
//  Los parametros por ola (k, omega, Q) los calcula la CPU UNA vez y los sube
//  como uniform: aqui NO se derivan, para que no haya dos calculos que puedan
//  dar resultados distintos.
// =============================================================================

const int OCEAN_MAX_WAVES = 16;

// wave_a[i] = (dir.x, dir.z, amplitud, k)        k = numero de onda = TAU/longitud
// wave_b[i] = (omega, fase, Q, --)               omega = sqrt(g*k), Q = steepness
uniform vec4 wave_a[OCEAN_MAX_WAVES];
uniform vec4 wave_b[OCEAN_MAX_WAVES];
uniform int wave_count = 8;
uniform float ocean_time = 0.0;

// -----------------------------------------------------------------------------
// Desplazamiento de Gerstner en un punto del plano horizontal.
// Devuelve (dx, altura, dz). OJO: es el desplazamiento DESDE la posicion de
// reposo `p`, no la posicion final.
// -----------------------------------------------------------------------------
vec3 ocean_displacement(vec2 p, float t) {
	vec3 d = vec3(0.0);
	for (int i = 0; i < wave_count; i++) {
		vec2 dir = wave_a[i].xy;
		float amp = wave_a[i].z;
		float k = wave_a[i].w;
		float omega = wave_b[i].x;
		float phase = wave_b[i].y;
		float q = wave_b[i].z;

		float theta = k * dot(dir, p) - omega * t + phase;
		float c = cos(theta);

		d.y += amp * sin(theta);
		d.x += q * amp * dir.x * c;
		d.z += q * amp * dir.y * c;
	}
	return d;
}

// -----------------------------------------------------------------------------
// Jacobiano del desplazamiento horizontal.
//   J < 0  =>  la cresta se pliega sobre si misma  =>  LA OLA ROMPE AQUI.
// Es a la vez la mascara de espuma y el criterio de daño del juego: el feedback
// visual y el mecanico salen del MISMO numero, asi que el jugador siempre puede
// leer donde le va a pegar el mar.
// -----------------------------------------------------------------------------
float ocean_jacobian(vec2 p, float t) {
	float dxdx = 0.0;
	float dzdz = 0.0;
	float dxdz = 0.0;
	for (int i = 0; i < wave_count; i++) {
		vec2 dir = wave_a[i].xy;
		float amp = wave_a[i].z;
		float k = wave_a[i].w;
		float omega = wave_b[i].x;
		float phase = wave_b[i].y;
		float q = wave_b[i].z;

		float theta = k * dot(dir, p) - omega * t + phase;
		float s = sin(theta);
		float qak = q * amp * k * s;

		dxdx -= qak * dir.x * dir.x;
		dzdz -= qak * dir.y * dir.y;
		dxdz -= qak * dir.x * dir.y;
	}
	return (1.0 + dxdx) * (1.0 + dzdz) - dxdz * dxdz;
}

// -----------------------------------------------------------------------------
// Normal analitica de la superficie. Espejo de OceanWaveProxy.normal_at().
// Se calcula en el vertex shader y se interpola: sale mas barato y mas estable
// que derivarla en el fragment, y sobre todo coincide con lo que ve la CPU.
// -----------------------------------------------------------------------------
vec3 ocean_normal(vec2 p, float t) {
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < wave_count; i++) {
		vec2 dir = wave_a[i].xy;
		float amp = wave_a[i].z;
		float k = wave_a[i].w;
		float omega = wave_b[i].x;
		float phase = wave_b[i].y;
		float q = wave_b[i].z;

		float theta = k * dot(dir, p) - omega * t + phase;
		float qaks = q * amp * k * sin(theta);
		float akc = amp * k * cos(theta);

		tangent.x -= qaks * dir.x * dir.x;
		tangent.y += akc * dir.x;
		tangent.z -= qaks * dir.x * dir.y;

		binormal.x -= qaks * dir.x * dir.y;
		binormal.y += akc * dir.y;
		binormal.z -= qaks * dir.y * dir.y;
	}
	return normalize(cross(binormal, tangent));
}

// -----------------------------------------------------------------------------
// DETALLE DE ALTA FRECUENCIA - SOLO VISUAL. LA FISICA NUNCA LO VE.
//
// Es el contrato k_split del plan, en miniatura: por debajo de cierta longitud
// de onda la energia deja de mover cuerpos y pasa a ser textura de superficie.
// Aqui el corte esta en ~8 m, que es donde la malla (celda de 2 m) ya no puede
// representar la ola de todas formas.
//
// Devuelve solo el GRADIENTE, o sea que perturba la normal sin desplazar ni un
// vertice. Consecuencia importante: apagar esto no cambia el gameplay ni un
// milimetro, asi que el preset grafico BAJO se juega exactamente igual que el
// ALTO, y en multijugador dos clientes con presets distintos siguen viendo el
// barco en el mismo sitio.
// -----------------------------------------------------------------------------
const int OCEAN_DETAIL_OCTAVES = 4;
const vec4 OCEAN_DETAIL[OCEAN_DETAIL_OCTAVES] = {
	// (dir.x, dir.z, longitud de onda, peso)
	vec4( 0.862,  0.507, 7.30, 1.00),
	vec4(-0.423,  0.906, 4.10, 0.62),
	vec4( 0.978, -0.208, 2.20, 0.38),
	vec4(-0.707, -0.707, 1.15, 0.22)
};

vec2 ocean_detail_gradient(vec2 p, float t) {
	vec2 grad = vec2(0.0);
	for (int i = 0; i < OCEAN_DETAIL_OCTAVES; i++) {
		vec2 dir = OCEAN_DETAIL[i].xy;
		float wl = OCEAN_DETAIL[i].z;
		float weight = OCEAN_DETAIL[i].w;
		float k = 6.2831853 / wl;
		float omega = sqrt(9.81 * k);
		// La amplitud se mantiene proporcional a la longitud de onda para que
		// todas las octavas tengan la misma pendiente caracteristica.
		float amp = wl * 0.022 * weight;
		float theta = k * dot(dir, p) - omega * t;
		grad += dir * (amp * k * cos(theta));
	}
	return grad;
}
