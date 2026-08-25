class_name OceanDebugHUD
extends CanvasLayer

## HUD de debug del oceano. La perilla de furia en manos de alguien que hace de
## dios cabron es, literalmente, la mecanica que hay que validar en F1.
##
## Muestra el numero que mas importa del sistema: Hs OBJETIVO frente a Hs
## MEDIDO. Si divergen mucho es que las olas estan saturando en su limite de
## rotura, que es correcto y deseable, pero hay que verlo y no adivinarlo.

@export var parity_markers_path: NodePath
@export var boat_path: NodePath
@export var director_path: NodePath
@export var day_night_path: NodePath
@export var rod_path: NodePath
@export var lightning_path: NodePath

@export_group("Lanzador de tsunamis")
## Los tiers que apareceran como botones, en orden. Las teclas 1..N los lanzan.
@export var tsunami_tiers: Array[TsunamiTier] = []
## Segundos hasta el impacto con los que se lanza. Ajustable con el deslizador.
@export var default_lead_seconds: float = 40.0
## De donde viene, en grados. 90 = desde +Z.
@export var tsunami_from_direction_deg: float = 90.0

@onready var _slider: HSlider = %FurySlider
@onready var _readout: RichTextLabel = %Readout
@onready var _presets: HBoxContainer = %Presets
@onready var _parity_toggle: CheckButton = %ParityToggle
@onready var _tsunami_buttons: HBoxContainer = %TsunamiButtons
@onready var _lead_slider: HSlider = %LeadSlider
@onready var _lead_label: Label = %LeadLabel
@onready var _rain_slider: HSlider = %RainSlider
@onready var _rain_label: Label = %ClimaLabel
@onready var _hour_slider: HSlider = %HourSlider
@onready var _hour_buttons: HBoxContainer = %HourButtons
@onready var _horario_label: Label = %HorarioLabel
@onready var _thunder_buttons: HBoxContainer = %ThunderButtons
@onready var _bolt_buttons: HBoxContainer = %BoltButtons
@onready var _reduce_flash: CheckButton = %ReduceFlashToggle
@onready var _parte_buttons: HBoxContainer = %ParteButtons
@onready var _agua_slider: HSlider = %AguaSlider
@onready var _agua_buttons: HBoxContainer = %AguaButtons
@onready var _agua_label: Label = %AguaLabel
@onready var _parte_label: Label = %ParteLabel

var _parity_markers: Node3D
var _boat: FloatingBody3D
var _director: TsunamiDirector
var _day_night: DayNightCycle
var _rod: FishingRod
var _lightning: LightningDirector
var _slam_flash: float = 0.0
var _peak_wave: float = 0.0


func _ready() -> void:
	_parity_markers = get_node_or_null(parity_markers_path) as Node3D
	_boat = get_node_or_null(boat_path) as FloatingBody3D
	_director = get_node_or_null(director_path) as TsunamiDirector
	_day_night = get_node_or_null(day_night_path) as DayNightCycle
	_rod = get_node_or_null(rod_path) as FishingRod
	_lightning = get_node_or_null(lightning_path) as LightningDirector

	_slider.min_value = 0.0
	_slider.max_value = 10.0
	_slider.step = 0.1
	_slider.value = Ocean.fury
	_slider.value_changed.connect(_on_fury_changed)

	for preset in [0, 3, 5, 8, 10]:
		var btn := Button.new()
		btn.text = str(preset)
		btn.custom_minimum_size = Vector2(36, 0)
		btn.pressed.connect(_on_preset.bind(float(preset)))
		_presets.add_child(btn)

	_parity_toggle.toggled.connect(_on_parity_toggled)
	if _parity_markers != null:
		_parity_toggle.button_pressed = _parity_markers.visible

	if _boat != null:
		_boat.slammed.connect(_on_slam)

	_build_tsunami_launcher()
	_build_clima()
	_build_agua()

	# El menu nace CERRADO: la puerta es la Ñ. Se hace aqui y no en las dos
	# escenas que lo instancian para que no puedan discrepar —y para que la
	# tercera que venga lo herede sin que nadie se acuerde.
	_abrir_menu(false)


# =============================================================================
#  Clima y horario
# =============================================================================

## El modo lluvia: el deslizador ES la lluvia (Ocean.rain_level). Es
## independiente de la furia a proposito — furia 9 con cielo seco es un estado
## valido del juego. El horario mueve SOLO el offset del ciclo dia/noche, jamas
## sim_time: adelantar el reloj del oceano teletransportaria las olas.
func _build_clima() -> void:
	_rain_slider.value = Ocean.rain_level
	_rain_slider.value_changed.connect(_on_rain_slider_changed)
	_build_thunder_buttons()
	_build_bolt_buttons()
	_build_parte_buttons()

	if _day_night == null:
		# Sin ciclo dia/noche en la escena no hay horario que tocar.
		_hour_slider.editable = false
		_horario_label.text = "HORARIO (sin ciclo dia/noche)"
		return
	_hour_slider.value_changed.connect(_on_hour_slider_changed)
	for step in [-1.0, 1.0, 3.0]:
		var btn := Button.new()
		btn.text = "%+d h" % int(step)
		btn.custom_minimum_size = Vector2(52, 0)
		btn.pressed.connect(_day_night.advance_hours.bind(step))
		_hour_buttons.add_child(btn)


## Un boton por REGIMEN de distancia, no por archivo: lo que hay que poder oir
## de un tirón es como cambia el trueno al alejarse (el crack se pierde y queda
## solo el retumbe, porque el aire se come los agudos — docs/CLIMA.md §2.6).
const THUNDER_PRESETS: Array = [
	["encima", 120.0],
	["cerca", 600.0],
	["medio", 1400.0],
	["lejos", 2800.0],
]


func _build_thunder_buttons() -> void:
	for preset: Array in THUNDER_PRESETS:
		var btn := Button.new()
		btn.text = preset[0]
		btn.tooltip_text = "Trueno a %.0f m (retardo real %.1f s tras el rayo)" % [
			preset[1], preset[1] / 343.0]
		btn.pressed.connect(WeatherAudio.play_thunder.bind(preset[1]))
		_thunder_buttons.add_child(btn)


## Un rayo A DEMANDA. Se suma encima de la secuencia determinista en vez de
## alterarla: el resto de la tormenta sigue siendo identica en todas las
## maquinas aunque aqui se aprieten botones.
const BOLT_PRESETS: Array = [
	["encima", 200.0],
	["cerca", 700.0],
	["lejos", 2400.0],
]


func _build_bolt_buttons() -> void:
	if _lightning == null:
		_reduce_flash.disabled = true
		return
	for preset: Array in BOLT_PRESETS:
		var btn := Button.new()
		btn.text = preset[0]
		btn.tooltip_text = "Rayo a %.0f m: el trueno llega %.1f s despues" % [
			preset[1], preset[1] / 343.0]
		btn.pressed.connect(_lightning.force_strike.bind(preset[1]))
		_bolt_buttons.add_child(btn)
	_reduce_flash.button_pressed = _lightning.reduce_flashes
	# NUNCA se etiqueta como "apto para epilepsia": describe el efecto, no
	# promete seguridad medica (responsabilidad legal, docs/CLIMA.md §2.5).
	_reduce_flash.tooltip_text = "Un solo destello suave por rayo, con la mitad de intensidad."
	_reduce_flash.toggled.connect(func(on: bool) -> void: _lightning.reduce_flashes = on)


## Un boton por CALADERO, no por «intensidad de tormenta»: el techo de furia
## es la promesa que el jugador compra al elegir donde pescar (DISENO), y lo
## que hay que poder validar de un tiron es que esa promesa se cumple —incluido
## el cielo, porque la lluvia no puede pasar de furia/6.
##
## Generar un parte NO es lo mismo que subir la furia: escribe el clima entero
## de la salida por adelantado y se lo da al mar. A partir de ahi el deslizador
## de furia sigue funcionando, pero suspende el guion (y avisa).
const CALADEROS: Array = [
	["BAHIA", 3.0],
	["BANCO", 5.0],
	["FOSA", 7.0],
	["NEGRAS", 9.0],
]

func _build_parte_buttons() -> void:
	for preset: Array in CALADEROS:
		var btn := Button.new()
		btn.text = preset[0]
		btn.tooltip_text = ("Escribe el parte de una salida en %s (techo de furia %.0f, "
			+ "asi que la lluvia no puede pasar de %.2f).") % [
				preset[0], preset[1], GeneradorParte.lluvia_maxima(preset[1])]
		btn.pressed.connect(_on_generar_parte.bind(float(preset[1])))
		_parte_buttons.add_child(btn)

	var off := Button.new()
	off.text = "sin parte"
	off.tooltip_text = "Vuelve al carril manual: la furia obedece solo al deslizador."
	off.pressed.connect(_on_quitar_parte)
	_parte_buttons.add_child(off)


## Como todo mando que MUTA el mar, en red se le pide al host en vez de mutar la
## copia local: el guion tiene que ser el MISMO en las seis maquinas o los rayos
## (que se deciden con la furia del spline) saldrian distintos en cada pantalla.
func _on_generar_parte(techo: float) -> void:
	# El director de tsunamis escribe `Ocean.fury` en CADA tick de su acto, y
	# eso suspende el parte al frame siguiente de crearlo. Se para, igual que
	# hace `_launch_tier`: a partir de aqui manda el guion. Sin esto, generar un
	# parte en `tsunami.tscn` era un no-op silencioso.
	if _director != null:
		_director.stop()
	if Net.pedir_debug(Net.Debug.PARTE, techo):
		return
	# Sin duracion: la sortea la semilla entre 10 y 25 min (GeneradorParte).
	Ocean.generar_parte(techo)


func _on_quitar_parte() -> void:
	if Net.pedir_debug(Net.Debug.PARTE_OFF, 0.0):
		return
	Ocean.limpiar_parte()


## Llenar el barco a mano, que es la unica forma practica de MIRAR el agua: por
## lluvia sola son once minutos hasta la alarma, y esperar una tormenta entera
## para juzgar si un charco se lee como charco no es forma de trabajar.
##
## Los botones son los tres momentos que el jugador tiene que reconocer de un
## vistazo, y por eso llevan el nombre de lo que se VE y no el numero: el dia que
## alguien mueva los umbrales del balance, estos botones tienen que moverse con
## ellos o dejan de enseñar lo que dicen.
const AGUA_PRESETS: Array = [
	["seco", 0.0],
	["charco", 0.05],
	["rodilla", 0.55],
	["cintura", 0.85],
]


func _build_agua() -> void:
	if _boat == null:
		_agua_slider.editable = false
		_agua_label.text = "AGUA EN CUBIERTA (sin barco en la escena)"
		return
	_agua_slider.value_changed.connect(_on_agua_slider_changed)
	for preset: Array in AGUA_PRESETS:
		var btn := Button.new()
		btn.text = String(preset[0])
		btn.custom_minimum_size = Vector2(62, 0)
		btn.tooltip_text = "Deja el barco con el %.0f %% de agua." % (float(preset[1]) * 100.0)
		btn.pressed.connect(_on_agua_preset.bind(float(preset[1])))
		_agua_buttons.add_child(btn)


func _on_agua_preset(nivel: float) -> void:
	# Mover el deslizador dispara `value_changed`, asi que el mando y los botones
	# no pueden discrepar.
	_agua_slider.value = nivel


func _on_agua_slider_changed(value: float) -> void:
	if Net.pedir_debug(Net.Debug.AGUA, value):
		return
	var agua := _agua_del_barco()
	if agua != null:
		agua.fijar_nivel(value)


func _agua_del_barco() -> AguaEmbarcada:
	if _boat == null:
		return null
	return _boat.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada


func _on_rain_slider_changed(value: float) -> void:
	if Net.pedir_debug(Net.Debug.LLUVIA, value):
		return
	Ocean.rain_level = value


func _on_hour_slider_changed(value: float) -> void:
	if Net.pedir_debug(Net.Debug.HORA, value):
		return
	_day_night.set_debug_hour(value)


## El deslizador de horario sigue al reloj (el dia avanza solo), y el de
## lluvia refleja rain_level aunque lo escriba otro (director, capturas).
##
## Con PARTE en vigor el deslizador de lluvia se apaga y pasa a ser un
## indicador. Dejarlo clicable seria el mismo pecado que un guion que ignora la
## perilla de furia: mueves el control, no pasa nada, y nadie te dice por que
## — el parte escribe `_rain` directamente y `rain_level` se queda de adorno.
## La furia NO se apaga nunca: esa perilla es sagrada y en su lugar SUSPENDE el
## guion (y lo dice en el readout).
func _sync_clima_controls() -> void:
	var con_parte: bool = Ocean.tiene_parte()
	_rain_slider.editable = not con_parte
	_rain_slider.set_value_no_signal(Ocean.rain01 if con_parte else Ocean.rain_level)
	_rain_label.text = "LLUVIA  (la manda el parte)" if con_parte else "LLUVIA"
	if _day_night != null:
		_hour_slider.set_value_no_signal(_day_night.hour())


# =============================================================================
#  Lanzador de tsunamis
# =============================================================================

func _build_tsunami_launcher() -> void:
	_lead_slider.min_value = 8.0
	_lead_slider.max_value = 120.0
	_lead_slider.step = 1.0
	_lead_slider.value = default_lead_seconds
	_lead_slider.value_changed.connect(func(_v: float) -> void: _update_lead_label())
	_update_lead_label()

	for i in tsunami_tiers.size():
		var tier: TsunamiTier = tsunami_tiers[i]
		if tier == null:
			continue
		var btn := Button.new()
		btn.text = "%d · %s" % [i + 1, tier.tier_name]
		btn.tooltip_text = tier.summary()
		btn.pressed.connect(_launch_tier.bind(tier))
		_tsunami_buttons.add_child(btn)

	var clear_btn := Button.new()
	clear_btn.text = "0 · limpiar"
	clear_btn.tooltip_text = "Cancela el tsunami en curso."
	clear_btn.pressed.connect(_clear_tsunami)
	_tsunami_buttons.add_child(clear_btn)


func _update_lead_label() -> void:
	_lead_label.text = "AVISO: %.0f s hasta el impacto" % _lead_slider.value


# =============================================================================
#  La puerta: la tecla Ñ
# =============================================================================

## `ñ` y `Ñ` en Unicode. Godot no tiene constante para esta tecla.
const UNICODE_ENE: int = 241
const UNICODE_ENE_MAYUS: int = 209


## Abre o cierra el menu entero.
##
## Cerrado no es "el panel esta invisible": es que la puerta esta cerrada y
## dentro no hay nada encendido. Por eso tambien se apaga el `_process`: el
## readout se rehace ENTERO cada frame con un RichTextLabel y no hay nadie
## leyendolo; al abrir vuelve completo en el primer frame.
func _abrir_menu(abierto: bool) -> void:
	visible = abierto
	set_process(abierto)
	if abierto:
		_sync_clima_controls()


## ¿Es la tecla que abre el menu? Godot no tiene `KEY_Ñ` —el enum `Key` se
## queda en los simbolos latinos basicos—, asi que hay que reconocerla por las
## tres vias que puede dar un teclado, y ninguna sirve sola:
##
## - `unicode`: lo que la tecla ESCRIBE (ñ 241 / Ñ 209). Es la via normal en un
##   teclado español, pero un evento sintetico (los arneses) puede no traerla.
## - `key_label`: la etiqueta LOCALIZADA de la tecla, que en Godot puede ser
##   cualquier Unicode. Aguanta cuando el evento no genera texto.
## - `physical_keycode`: la POSICION de la Ñ española, que en un QWERTY US es la
##   del `;`. Sin esto, quien no tenga Ñ en su teclado se quedaria sin menu de
##   debug y sin forma de enterarse de por que.
##
## Es `static` para que se pueda probar sin levantar una escena: lo que se rompe
## aqui —una tecla que en otra distribucion no llega— no grita, solo deja de
## abrir.
static func es_tecla_menu(tecla: InputEventKey) -> bool:
	if tecla.unicode == UNICODE_ENE or tecla.unicode == UNICODE_ENE_MAYUS:
		return true
	if tecla.key_label == UNICODE_ENE or tecla.key_label == UNICODE_ENE_MAYUS:
		return true
	return tecla.physical_keycode == KEY_SEMICOLON


## La Ñ abre y cierra; el resto de teclas son 1..N para los tiers y 0 para
## limpiar.
##
## Los botones no bastan: durante el playtest el raton esta CAPTURADO porque
## estas de pie en la cubierta, asi que no puedes hacer clic sin soltarlo antes
## y perder justo el momento que querias provocar.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var tecla := event as InputEventKey
	if es_tecla_menu(tecla):
		_abrir_menu(not visible)
		get_viewport().set_input_as_handled()
		return
	# Con el menu cerrado sus atajos NO existen. Si respondieran, cerrarlo seria
	# solo apagar la luz: `B` seguiria reflotando el barco y `P` escribiendo un
	# temporal entero a un dedo de distancia en mitad de una partida.
	if not visible:
		return
	var key := tecla.keycode
	if key == KEY_0:
		_clear_tsunami()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_N and _day_night != null:
		_day_night.advance_hours(3.0)
		get_viewport().set_input_as_handled()
		return
	# C cicla el arbol de cañas (la caña se niega sola si esta en plena faena).
	# Misma razon que las teclas de tsunami: con el raton capturado en cubierta
	# no hay boton clicable, y validar el balance exige cambiar de aparejo al vuelo.
	if key == KEY_C and _rod != null:
		_rod.cycle_tier()
		get_viewport().set_input_as_handled()
		return
	# T dispara un trueno de prueba a distancia aleatoria: valida mezcla,
	# ducking y variante-por-distancia sin esperar a la fase C (el scheduling
	# determinista de rayos es del LightningDirector).
	if key == KEY_T:
		WeatherAudio.play_thunder(randf_range(150.0, 2600.0))
		get_viewport().set_input_as_handled()
		return
	# R: rayo completo (destello + bolt + trueno con su retardo real).
	if key == KEY_R and _lightning != null:
		_lightning.force_strike(randf_range(200.0, 1800.0))
		get_viewport().set_input_as_handled()
		return
	# P: escribe un parte nuevo para el caladero mas duro. Con el raton
	# capturado en cubierta no hay boton clicable, y lo que hay que poder
	# provocar al vuelo es justo la tormenta guionada.
	if key == KEY_P:
		_on_generar_parte(9.0)
		get_viewport().set_input_as_handled()
		return
	# B: reflotar el barco (seco, a flote y adrizado). Hasta que exista el puerto
	# es la unica salida de un naufragio, y sin ella validar el achique obliga a
	# reiniciar la escena cada vez que el mar gana.
	if key == KEY_B:
		_reflotar()
		get_viewport().set_input_as_handled()
		return
	var index := key - KEY_1
	if index >= 0 and index < tsunami_tiers.size() and tsunami_tiers[index] != null:
		_launch_tier(tsunami_tiers[index])
		get_viewport().set_input_as_handled()


## En red, los mandos que MUTAN el mar se reenvian al host en vez de mutar la
## copia local. Bloquearlos rompe el juguete —CLAUDE.md dice que la perilla de
## furia en manos de alguien haciendo de dios ES la herramienta de validacion
## de F1—, y dejarlos divergir rompe el mar. Reenviar es lo unico honesto; y en
## un coop de amigos, que cualquiera pueda tirar un tsunami es una FEATURE.
func _launch_tier(tier: TsunamiTier) -> void:
	# El director tiene su propio ciclo y volveria a llamar a `clear_events()`,
	# asi que se detiene: a partir de aqui manda el lanzador.
	if _director != null:
		_director.stop()
	# El HOST recalcula el objetivo con SU barco: el del cliente es la copia
	# INTERPOLADA, que esta en otro sitio. Menos bytes y ademas correcto.
	if Net.pedir_tsunami(_target_position(), tsunami_from_direction_deg,
			_lead_slider.value, tier):
		return
	if Net.en_red():
		# Cliente: se pide limpiar y lanzar, EN ORDEN — `_launch_tier` hace dos
		# mutaciones y replicar solo la segunda dejaria la ola vieja MAS la
		# nueva, con los dos slots quemados.
		Net.pedir_debug(Net.Debug.LIMPIAR, 0.0)
		Net.pedir_tsunami_cliente(tsunami_from_direction_deg, _lead_slider.value, tier)
		return
	Ocean.spawn_tsunami_tier(_target_position(), tsunami_from_direction_deg,
		_lead_slider.value, tier)


## Reflotar va por la MISMA via que el resto de mandos: el agua es
## host-autoritativa, asi que un cliente pide y el host ejecuta y difunde. En
## solitario `pedir_debug` devuelve false y se hace en local, como todo lo demas.
func _reflotar() -> void:
	if Net.pedir_debug(Net.Debug.REFLOTE, 0.0):
		return
	if _boat == null:
		return
	var agua := _boat.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	if agua != null:
		agua.reflotar()


func _clear_tsunami() -> void:
	if Net.pedir_debug(Net.Debug.LIMPIAR, 0.0):
		return
	Ocean.clear_events()


## Hacia donde apunta el tsunami: el barco si lo hay, si no la camara.
func _target_position() -> Vector3:
	if _boat != null:
		return _boat.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


func _on_fury_changed(value: float) -> void:
	# Por el slider se usa la rampa: mover el dial de golpe es justo lo que el
	# rate limit esta para evitar.
	if Net.pedir_debug(Net.Debug.FURIA, value):
		return
	Ocean.fury = value


func _on_preset(value: float) -> void:
	_slider.set_value_no_signal(value)
	if Net.pedir_debug(Net.Debug.FURIA_YA, value):
		return
	Ocean.set_fury_immediate(value)


func _on_parity_toggled(pressed: bool) -> void:
	if _parity_markers != null:
		_parity_markers.visible = pressed


func _on_slam(strength: float, _pos: Vector3) -> void:
	_slam_flash = maxf(_slam_flash, minf(strength, 3.0))


func _process(delta: float) -> void:
	_slam_flash = maxf(_slam_flash - delta * 2.0, 0.0)
	_sync_clima_controls()

	var cam := get_viewport().get_camera_3d()
	var here := cam.global_position if cam != null else Vector3.ZERO
	var wave_here := Ocean.get_height(here)
	_peak_wave = maxf(_peak_wave * 0.995, absf(wave_here))

	var breaking := Ocean.get_breaking(here)
	var steep := Ocean.steepness_sum()

	var lines := PackedStringArray()

	if Ocean.has_tsunami():
		var eta := Ocean.time_until_tsunami(here)
		var act_label := _director.act_name() if _director != null else "TSUNAMI"
		if Ocean.current_tier != null:
			act_label = "%s  ·  %s" % [Ocean.current_tier.tier_name, act_label]
		if _director != null and not _director.is_running():
			act_label += "  (manual)"
		# El color del contador es la telegrafia: pasa a rojo cuando ya no da
		# tiempo a hacer nada.
		var col := "#8fe388"
		if eta < 10.0:
			col = "#ff6b6b"
		elif eta < 55.0:
			col = "#ffd166"
		lines.append("[color=%s][b]%s[/b][/color]" % [col, act_label])
		if eta > -30.0 and eta < 900.0:
			lines.append("[color=%s][b]impacto en %+.1f s[/b][/color]" % [col, eta])
		# Altura que el tsunami aporta AQUI: negativa mientras el mar se retira.
		var ev_h := Ocean.get_events().height_at(Vector2(here.x, here.z), Ocean.sim_time)
		lines.append("aporte del evento %+.2f m" % ev_h)
		lines.append("")

	lines.append("[b]MAR[/b]")
	lines.append("furia            [b]%.2f[/b] / 10" % Ocean.fury)
	lines.append("Hs objetivo      %.2f m" % Ocean.target_hs())
	lines.append("Hs medido        [color=%s]%.2f m[/color]" % [
		"#8fe388" if absf(Ocean.measured_hs() - Ocean.target_hs()) < 0.5 else "#e3c988",
		Ocean.measured_hs()
	])
	lines.append("steepness        [color=%s]%.3f[/color] / %.2f" % [
		"#8fe388" if steep <= OceanWaveProxy.STEEPNESS_LIMIT else "#e38888",
		steep, OceanWaveProxy.STEEPNESS_LIMIT
	])
	lines.append("altura aqui      %.2f m  (pico %.1f)" % [wave_here, _peak_wave])
	lines.append("jacobiano        [color=%s]%.3f[/color]  %s" % [
		"#e38888" if breaking < 0.0 else "#8fe388",
		breaking,
		"ROMPIENDO" if breaking < 0.0 else ""
	])
	lines.append("t simulacion     %.1f s" % Ocean.sim_time)
	var rain_note := ""
	if Ocean.rain_scale <= 0.0 and Ocean.rain_level > 0.0:
		rain_note = "  [color=#ffd166](cortada por el acto)[/color]"
	lines.append("lluvia           [b]%.2f[/b]%s" % [Ocean.rain01, rain_note])
	lines.append("viento           %.1f m/s  ·  racha %.2f" % [Ocean.wind_speed(), Ocean.gust01()])
	if _lightning != null:
		var next: float = _lightning.seconds_to_next_strike()
		lines.append("rayo             %s%s" % [
			"en %.0f s" % next if next < 900.0 else "sin actividad",
			"  [color=#ffd166]FLASH[/color]" if _lightning.intensity_at(Ocean.sim_time) > 0.05 else ""])
	if _day_night != null:
		lines.append("hora             [b]%s[/b]  %s" % [
			_day_night.clock_text(),
			"[color=#9db4e8]NOCHE[/color]" if _day_night.is_night() else "[color=#e8d99d]DIA[/color]"])

	# EL PARTE. Es la unica parte del HUD que mira al FUTURO, asi que es
	# tambien la unica forma de comprobar a ojo que la consulta no miente:
	# lo que dice aqui tiene que ser lo que pase dentro de ese tiempo.
	lines.append("")
	lines.append("[b]PARTE[/b]")
	if Ocean.tiene_parte():
		var t: float = Ocean.sim_time
		var swell: float = Ocean.furia_swell(t, 300.0)
		# Un guion agotado sigue respondiendo (mantiene el ultimo valor) pero ya
		# no promete nada: el clima esta congelado. Decirlo, porque «en vigor
		# si» con el mar clavado se lee como un bug del mar.
		lines.append("en vigor         %s" % ("[color=#ffd166]AGOTADO (clima congelado)[/color]"
			if Ocean.parte_agotado() else "[color=#8fe388]si[/color]"))
		lines.append("dentro de 1 min  furia %.1f  ·  lluvia %.2f" % [
			Ocean.furia_en(t + 60.0), Ocean.lluvia_en(t + 60.0)])
		lines.append("dentro de 5 min  furia %.1f  ·  lluvia %.2f" % [
			Ocean.furia_en(t + 300.0), Ocean.lluvia_en(t + 300.0)])
		# El mar de fondo se adelanta a la tormenta: esta linea es LO que hace
		# posible telegrafiarlo (docs/CLIMA.md §3.3).
		lines.append("pico que viene   [b]%.1f[/b]  %s" % [swell,
			"[color=#ffd166](+%.1f)[/color]" % (swell - Ocean.fury)
				if swell > Ocean.fury + 0.3 else ""])
	else:
		lines.append("sin guion        (la furia obedece al deslizador)")

	if _rod != null:
		lines.append("")
		lines.append("[b]CAÑA[/b]  " + _rod.debug_line())

	if _boat != null:
		lines.append("")
		lines.append("[b]BARCO[/b]")
		lines.append("sumergido        %.0f%%" % (_boat.submerged_fraction * 100.0))
		# El agua embarcada, celda a celda: la media sola no dice DONDE esta el
		# agua, que es justo lo que decide a que celda llevar la manguera.
		var agua := _boat.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
		var estado := ""
		if agua != null:
			if agua.hundido:
				estado = "  [color=#f05a4b]NAUFRAGIO[/color]"
			elif agua.alarma:
				estado = "  [color=#ffb020]ALARMA[/color]"
		# El numero es el nivel A BORDO —celdas mas lo que las bombas llevan
		# chupado y aun no han escupido—, que es EL MISMO con el que se deciden la
		# alarma y el naufragio que se pintan aqui al lado. Poner solo las celdas
		# dejaba el HUD diciendo "82 %  NAUFRAGIO", con el estado y su causa
		# discrepando en la misma linea.
		var a_bordo: float = agua.nivel if agua != null else _boat.flooding_level()
		lines.append("inundacion       [b]%.0f%%[/b]%s" % [a_bordo * 100.0, estado])
		if agua != null and agua.agua_en_depositos() > 0.0:
			lines.append("  en bombas      %.1f%%" % (agua.agua_en_depositos() * 100.0))
		if _boat.probe_count() > 0:
			var celdas := ""
			for i in _boat.probe_count():
				celdas += "%3.0f" % (_boat.probe_flooding(i) * 100.0)
			lines.append("celdas          %s" % celdas)
		lines.append("velocidad        %.1f m/s" % _boat.linear_velocity.length())
		if _slam_flash > 0.0:
			lines.append("[color=#ffd166][b]IMPACTO %.1f[/b][/color]" % _slam_flash)

	lines.append("")
	lines.append("[b]RENDIMIENTO[/b]")
	lines.append("fps              %d" % Engine.get_frames_per_second())
	lines.append("fisica           %.2f ms" % (
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0))
	lines.append("proceso          %.2f ms" % (
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))

	_readout.text = "\n".join(lines)
