shader_type canvas_item;
render_mode unshaded;

// =============================================================================
//  SONDA DE PARIDAD  —  la GPU contestando por escrito
// =============================================================================
//  Evalua LA MISMA matematica que dibuja el mar y escupe el resultado como
//  pixeles, para que la CPU pueda leerlo y compararse contra el.
//
//  [b]Por que un shader 2D y no uno espacial.[/b] Lo que hay que capturar es el
//  valor NUMERICO de `ocean_displacement()`, no un mar dibujado. Con un shader
//  espacial habria que rasterizar geometria y volver a leer alturas de la
//  imagen, con proyeccion, profundidad e interpolacion de por medio. Aqui cada
//  pixel ES una muestra: uno entra, uno sale, sin nada que pueda deformarla.
//
//  [b]Por que incluye el mismo .gdshaderinc y no una copia.[/b] Porque una
//  copia haria que este test comprobara la copia. El include es exactamente el
//  archivo que usa `ocean_surface.gdshader`, y los uniforms los empaqueta el
//  MISMO `Ocean.apply_to_material()` que alimenta al mar de verdad.
// =============================================================================

#include "res://addons/ocean/shaders/ocean_waves.gdshaderinc"

// 0 = desplazamiento x, 1 = altura, 2 = desplazamiento z, 3 = jacobiano.
uniform int componente = 1;
// Rango simetrico al que se normaliza antes de empaquetar. Tiene que cubrir el
// peor caso con holgura: con furia 10 el Hs es de 25 m y el desplazamiento
// horizontal de Gerstner llega a ser comparable.
uniform float rango = 64.0;

// Posicion de reposo de la muestra (i, j).
//
// Los pasos 37 y 53 son primos y los modulos 977 y 991 tambien: la rejilla
// resultante NO se alinea con ninguna longitud de onda del banco, que es justo
// lo que hay que evitar. Una rejilla regular puede caer entera en los nodos de
// una ola y dar cero error mientras la formula esta rota.
//
// ⚠️ ESTA FUNCION ESTA DUPLICADA en `GoldenOceano.punto()`. Es duplicacion
// deliberada y del mismo tipo que la del propio oleaje: las dos caras del test
// tienen que poder calcular el punto por su cuenta. Si tocas una, toca la otra.
vec2 punto(int i, int j) {
	return vec2(
		float((i * 37) % 977) - 488.0,
		float((j * 53) % 991) - 495.0);
}

// Un float en [0,1] repartido entre TRES canales de 8 bits.
//
// Hace falta repartirlo porque un canal solo da 256 escalones, y sobre un rango
// de 128 m eso es medio metro por escalon: el test tiene que resolver 1 mm. Con
// tres canales quedan 24 bits, o sea ~8 micras. De sobra.
//
// TRES y no cuatro: el render target del SubViewport sale en RGB8 sin alfa
// (medido — la primera version leia 4 bytes por pixel y se salia del array a
// los 3072). Y meter el alfa tampoco seria gratis: al ser un canvas con
// mezcla, el alfa multiplicaria el RGB y corromperia justo lo que se quiere
// leer sin tocar.
vec3 empaquetar(float v) {
	v = clamp(v, 0.0, 0.99999994);
	vec3 enc = fract(v * vec3(1.0, 255.0, 65025.0));
	enc -= enc.yzz * vec3(1.0 / 255.0, 1.0 / 255.0, 0.0);
	return enc;
}

void fragment() {
	// FRAGCOORD y no UV: da el centro exacto del pixel (0.5, 1.5, ...), asi que
	// el indice sale de un floor y no de multiplicar un UV por un tamaño, que
	// es donde aparecen los off-by-one cuando el redondeo cae justo en el borde.
	int i = int(floor(FRAGCOORD.x));
	int j = int(floor(FRAGCOORD.y));
	vec2 p = punto(i, j);

	float v;
	if (componente == 3) {
		v = ocean_jacobian(p, ocean_time);
	} else {
		vec3 d = ocean_displacement(p, ocean_time);
		if (componente == 0) {
			v = d.x;
		} else if (componente == 1) {
			v = d.y;
		} else {
			v = d.z;
		}
	}

	COLOR = vec4(empaquetar(v / rango * 0.5 + 0.5), 1.0);
}
