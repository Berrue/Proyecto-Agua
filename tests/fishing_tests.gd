extends Node

## Pruebas de la caña.
##
##   godot --headless --path . tests/fishing_tests.tscn
##
## FightModel esta separado del nodo justo para esto: la matematica de la lucha
## se prueba directa, sin simular teclas. Lo que se protege: que el MAR entra de
## verdad en la tension (la tesis del juego), que la contra funciona, que la
## rotura avisa antes de romper (justicia), y que una lucha bien jugada TERMINA.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de pesca ---[/b]")
	_test_sea_enters_tension()
	_test_counter_works()
	_test_warn_before_snap()
	_test_snap_on_sustained_greed()
	_test_clean_fight_lands()
	_test_species_bands()
	_test_fish_takes_line()
	_test_hold_click_is_not_a_strategy()
	_test_slack_spits_with_warning()
	_test_fish_tires()
	_test_species_tiers()
	_test_doubled_roster()
	_test_tier_reaction_window()
	_test_legendary_is_rare()
	_test_rod_tiers_ladder()
	_test_rod_strengthens_line()
	_test_rod_reels_faster()
	_test_bait_never_raises_band()
	_test_bait_biases_to_the_big_one()
	await _test_bait_charges_and_bucket()
	await _test_staked_bite_window()
	await _test_fish_body()
	await _test_wiring()
	_test_sfx_library()
	_test_nibble_plan()
	await _test_camera_feedback()
	_test_lean_accompaniment()
	await _test_camera_drag()
	await _test_fishing_hud()
	_report()


## Tras el rig hay un BoneAttachment3D con el MISMO nombre que cada malla:
## buscar por tipo o el cast a MeshInstance3D devuelve null.
func _mesh_of(model: Node, part: String) -> MeshInstance3D:
	var found := model.find_children(part, "MeshInstance3D", true, false)
	return found[0] if not found.is_empty() else null


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		print("  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""])
		_failures.append(label + (" :: " + detail if detail != "" else ""))


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones OK[/b][/color]" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d han fallado:[/b][/color]" % [_failures.size(), _checks])
		for f in _failures:
			print("   - " + f)
		get_tree().quit(1)


func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


func _sardina() -> Dictionary:
	return FishSpecies.SPECIES[0]


## Por nombre, no por indice: la tabla ahora termina en la legendaria.
func _atun() -> Dictionary:
	return _species_named("Atun")


func _species_named(species_name: String) -> Dictionary:
	for species in FishSpecies.SPECIES:
		if String(species[&"name"]) == species_name:
			return species
	return {}


# =============================================================================


## LA TESIS: el mismo pez con el mismo input tensa mas el sedal cuanto mas se
## mueve la cubierta. Si esto falla, la pesca y el mar son dos juegos separados.
func _test_sea_enters_tension() -> void:
	var calm := FightModel.new()
	calm.start(_sardina(), _rng(7))
	var storm := FightModel.new()
	storm.start(_sardina(), _rng(7)) # misma semilla: mismas fases del pez

	calm.step(0.1, false, FightModel.Pull.NONE, 0.0)
	storm.step(0.1, false, FightModel.Pull.NONE, 8.0) # borda de furia 7-8

	var diff: float = storm.tension - calm.tension
	_check(absf(diff - FightModel.SEA_K * 8.0) < 1e-6,
		"la aceleracion de la borda entra directa en la tension",
		"delta %.3f (esperado %.3f)" % [diff, FightModel.SEA_K * 8.0])


func _test_counter_works() -> void:
	var against := FightModel.new()
	against.start(_atun(), _rng(11))
	var with_it := FightModel.new()
	with_it.start(_atun(), _rng(11))

	# Misma semilla: ambos peces tiran en la misma direccion. Uno contra bien,
	# el otro contra MAL (a favor del tiron).
	var dir: FightModel.Pull = against.pull_dir
	var opposite: FightModel.Pull = FightModel.Pull.LEFT if dir == FightModel.Pull.RIGHT else FightModel.Pull.RIGHT
	against.step(0.1, false, opposite, 0.0)
	with_it.step(0.1, false, dir, 0.0)

	_check(against.tension < with_it.tension, "contrar bien reduce la tension",
		"contra %.2f vs error %.2f" % [against.tension, with_it.tension])
	_check(against.tension > 0.1, "pero no la anula: el pez sigue siendo un pez",
		"%.2f" % against.tension)


## JUSTICIA: entre "el carrete chirria" y "el sedal rompe" tiene que haber
## margen real de reaccion, en cualquier condicion.
func _test_warn_before_snap() -> void:
	_check(FightModel.WARN_TENSION < FightModel.SNAP_TENSION,
		"el aviso llega antes que la rotura")
	# Y la rotura exige SOSTENER la sobrecarga, no un pico de un frame.
	var m := FightModel.new()
	m.start(_atun(), _rng(3))
	m.step(0.1, true, FightModel.Pull.NONE, 20.0) # un solo tick brutal
	_check(not m.snapped, "un pico de un frame no rompe el sedal",
		"T=%.2f" % m.tension)


## La codicia rompe: recoger contra un atun que tira, con la cubierta de furia
## alta, tiene que partir el sedal en menos de dos segundos de insistencia.
func _test_snap_on_sustained_greed() -> void:
	var m := FightModel.new()
	m.start(_atun(), _rng(5))
	var t: float = 0.0
	while not m.snapped and t < 10.0:
		# Siempre recogiendo, siempre contrando MAL, mar de furia 7.
		m.step(1.0 / 60.0, true, m.pull_dir, 7.0)
		t += 1.0 / 60.0
	_check(m.snapped, "la codicia sostenida rompe el sedal")
	_check(not m.landed, "y el pez se pierde")


## Una lucha bien jugada (contrar el tiron, recoger solo en la pausa) TIENE que
## terminar con el pez fuera del agua, sin romper, en tiempo razonable.
func _test_clean_fight_lands() -> void:
	var m := FightModel.new()
	m.start(_sardina(), _rng(21))
	var t: float = 0.0
	while not m.landed and not m.snapped and t < 60.0:
		var counter := FightModel.Pull.NONE
		if m.pull_dir == FightModel.Pull.LEFT:
			counter = FightModel.Pull.RIGHT
		elif m.pull_dir == FightModel.Pull.RIGHT:
			counter = FightModel.Pull.LEFT
		m.step(1.0 / 60.0, not m.is_pulling(), counter, 1.0) # mar tranquilo
		t += 1.0 / 60.0
	_check(m.landed and not m.snapped, "la lucha limpia termina en captura",
		"landed=%s snapped=%s t=%.1f" % [m.landed, m.snapped, t])
	_check(t > 3.0 and t < 30.0, "y dura lo que una lucha (3-30 s)", "%.1f s" % t)


## Las bandas de especies respetan la furia: el pez caro vive en el mar malo.
func _test_species_bands() -> void:
	var rng := _rng(99)
	var calm_ok := true
	for _i in 300:
		var s := FishSpecies.choose(1.0, rng)
		if float(s[&"min_fury"]) > 1.0:
			calm_ok = false
	_check(calm_ok, "con furia 1 solo pican especies de calma")

	var saw_tuna := false
	for _i in 300:
		var s := FishSpecies.choose(7.5, rng)
		if String(s[&"name"]) == "Atun":
			saw_tuna = true
	_check(saw_tuna, "con furia 7.5 el atun existe")


## EL PEZ SE LLEVA SEDAL: durante el tiron sin contra el progreso BAJA, y la
## contra correcta lo frena a un cuarto. Sin esto no hay tira-y-afloja.
func _test_fish_takes_line() -> void:
	var free := FightModel.new()
	free.start(_atun(), _rng(31))
	var held := FightModel.new()
	held.start(_atun(), _rng(31)) # misma semilla: mismas fases

	var opposite: FightModel.Pull = FightModel.Pull.LEFT 		if free.pull_dir == FightModel.Pull.RIGHT else FightModel.Pull.RIGHT
	free.progress = 0.5
	held.progress = 0.5
	# Un segundo de tiron: uno lo deja correr, el otro contra bien.
	for _i in 60:
		if not free.is_pulling():
			break
		free.step(1.0 / 60.0, false, FightModel.Pull.NONE, 0.0)
		held.step(1.0 / 60.0, false, opposite, 0.0)
	_check(free.progress < 0.5, "el pez sin contra se lleva sedal",
		"progreso %.3f" % free.progress)
	_check(held.progress > free.progress, "la contra frena la sangria",
		"contra %.3f vs libre %.3f" % [held.progress, free.progress])


## LA QUEJA DEL PLAYTEST, convertida en test: mantener el clic sin hacer nada
## mas NO puede ganar rapido. Con un bacalao la tension de recoger contra el
## tiron tiene que acercarse a la rotura incluso en calma.
func _test_hold_click_is_not_a_strategy() -> void:
	var m := FightModel.new()
	m.start(_species_named("Bacalao"), _rng(41)) # Bacalao, pull 0.55
	var peak: float = 0.0
	var t: float = 0.0
	while not m.landed and not m.snapped and not m.escaped and t < 25.0:
		m.step(1.0 / 60.0, true, FightModel.Pull.NONE, 0.0) # solo mantener clic
		if m.is_pulling():
			peak = maxf(peak, m.tension)
		t += 1.0 / 60.0
	_check(peak >= FightModel.SNAP_TENSION,
		"recoger a lo bruto contra un bacalao roza la rotura incluso en calma",
		"pico %.2f" % peak)
	_check(m.snapped or t > 20.0, "y mantener clic no gana rapido",
		"landed=%s en %.1f s" % [m.landed, t])


## NO recoger tambien pierde: sedal flojo sostenido = el pez escupe, y el aviso
## llega ANTES del fallo (la regla de justicia, ahora tambien por defecto).
func _test_slack_spits_with_warning() -> void:
	var m := FightModel.new()
	m.start(_sardina(), _rng(51))
	var warned_before_escape := false
	var t: float = 0.0
	while not m.escaped and t < 30.0:
		if m.is_spit_warning() and not m.escaped:
			warned_before_escape = true
		m.step(1.0 / 60.0, false, FightModel.Pull.NONE, 0.0) # ignorar la caña
		t += 1.0 / 60.0
	_check(m.escaped, "ignorar la caña pierde el pez", "t=%.1f" % t)
	_check(warned_before_escape, "y el aviso llego ANTES del fallo")
	_check(not m.snapped, "escupir no es romper: fallo blando")


## El pez se cansa TIRANDO: los tirones se debilitan y se ve ganar sin barras.
func _test_fish_tires() -> void:
	var m := FightModel.new()
	m.start(_atun(), _rng(61))
	for _i in 600: # 10 s de lucha activa
		var counter: FightModel.Pull = FightModel.Pull.LEFT 			if m.pull_dir == FightModel.Pull.RIGHT else FightModel.Pull.RIGHT
		m.step(1.0 / 60.0, not m.is_pulling(), counter, 0.0)
		if m.landed or m.snapped or m.escaped:
			break
	_check(m.stamina < 0.9, "el pez se cansa peleando", "fuelle %.2f" % m.stamina)


# =============================================================================
#  Tiers de pez y de caña
# =============================================================================


## Todas las especies llevan tier 1-4 y el tier sigue a la banda de furia: el
## pez del mar bravo es el pez dificil. Sin esta coherencia, la ventana de
## reaccion por tier premiaria o castigaria al pez equivocado.
func _test_species_tiers() -> void:
	var ok := true
	for s in FishSpecies.SPECIES:
		var tier := FishSpecies.tier_of(s)
		if tier < 1 or tier > 4:
			ok = false
		if float(s[&"min_fury"]) < 3.0 and tier != 1:
			ok = false
		if float(s[&"min_fury"]) >= 6.0 and tier < 3:
			ok = false
	_check(ok, "toda especie tiene tier 1-4 coherente con su banda")
	_check(FishSpecies.tier_of(_sardina()) == 1 and FishSpecies.tier_of(_atun()) == 3,
		"sardina tier 1, atun tier 3")
	_check(FishSpecies.tier_of({&"name": "desconocido"}) == 1,
		"un pez sin tier cuenta como banda A (el fallo seguro es el indulgente)")


## La 2ª tanda: 16 especies (el doble por banda: 6/6/2/2) y la escalera de
## pull SIN solapes entre tiers — el tier ES la dificultad, sin excepciones
## que confundan la ventana de reaccion. Ademas, la calma sigue siendo de los
## tres comunes con modelo (el invariante de fish_asset_tests, protegido
## tambien desde aqui porque esta tabla es la que lo puede romper).
func _test_doubled_roster() -> void:
	_check(FishSpecies.SPECIES.size() == 16, "la tabla tiene 16 especies",
		"%d" % FishSpecies.SPECIES.size())

	var per_tier: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}
	var min_pull: Dictionary = {1: 99.0, 2: 99.0, 3: 99.0, 4: 99.0}
	var max_pull: Dictionary = {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0}
	var calm_pool: int = 0
	for s in FishSpecies.SPECIES:
		var tier := FishSpecies.tier_of(s)
		per_tier[tier] = int(per_tier[tier]) + 1
		min_pull[tier] = minf(float(min_pull[tier]), float(s[&"pull"]))
		max_pull[tier] = maxf(float(max_pull[tier]), float(s[&"pull"]))
		if float(s[&"min_fury"]) <= 1.0:
			calm_pool += 1
	_check(per_tier[1] == 6 and per_tier[2] == 6 and per_tier[3] == 2
		and per_tier[4] == 2, "el doble por banda: 6/6/2/2 especies por tier",
		str(per_tier))
	_check(float(max_pull[1]) < float(min_pull[2])
		and float(max_pull[2]) < float(min_pull[3])
		and float(max_pull[3]) < float(min_pull[4]),
		"la escalera de pull no se solapa entre tiers",
		"A %.2f-%.2f · B %.2f-%.2f · C %.2f-%.2f · L %.2f-%.2f" % [
			float(min_pull[1]), float(max_pull[1]), float(min_pull[2]), float(max_pull[2]),
			float(min_pull[3]), float(max_pull[3]), float(min_pull[4]), float(max_pull[4])])
	_check(calm_pool == 3, "en furia <=1 siguen picando SOLO los tres con modelo",
		"%d en el pool de calma" % calm_pool)


## Sobrecarga garantizada (recogiendo con un mar absurdo): cuanto tarda el
## sedal en partir desde que la tension entra en zona de rotura.
func _time_to_snap(species: Dictionary, rod: RodTier = null) -> float:
	var m := FightModel.new()
	m.start(species, _rng(13), rod)
	var t: float = 0.0
	while not m.snapped and t < 10.0:
		m.step(1.0 / 60.0, true, FightModel.Pull.NONE, 30.0)
		t += 1.0 / 60.0
	return t


## LA QUEJA DEL PLAYTEST ("el sedal rompe demasiado rapido"), convertida en
## test: la ventana de reaccion existe, es mayor cuanto mas humilde el pez, y
## ni el pez heroico rompe de un latigazo (regla 8: avisar Y dar tiempo).
func _test_tier_reaction_window() -> void:
	var descending := true
	for i in range(1, FightModel.SNAP_HOLD_BY_TIER.size()):
		if FightModel.SNAP_HOLD_BY_TIER[i] > FightModel.SNAP_HOLD_BY_TIER[i - 1]:
			descending = false
	_check(descending, "la ventana de reaccion encoge al subir el tier")

	var sardina_t := _time_to_snap(_sardina())
	var atun_t := _time_to_snap(_atun())
	var aguja_t := _time_to_snap(_species_named("Aguja azul"))
	_check(sardina_t >= 1.4, "la sardina da ~1.5 s para soltar el clic (antes: 0.5)",
		"%.2f s" % sardina_t)
	_check(atun_t <= sardina_t * 0.5, "el atun exige mas del doble de reflejos",
		"%.2f s vs %.2f s" % [atun_t, sardina_t])
	_check(aguja_t < atun_t and aguja_t >= 0.4,
		"la legendaria aprieta mas, pero jamas roba", "%.2f s" % aguja_t)


## La legendaria: no existe bajo su furia y en la suya pica a cuentagotas
## (~1 de cada 13 lances, documento de diseño §3).
func _test_legendary_is_rare() -> void:
	var rng := _rng(123)
	var below := 0
	for _i in 400:
		if FishSpecies.tier_of(FishSpecies.choose(6.5, rng)) == 4:
			below += 1
	_check(below == 0, "con furia 6.5 la legendaria ni existe")
	var seen := 0
	for _i in 600:
		if FishSpecies.tier_of(FishSpecies.choose(7.5, rng)) == 4:
			seen += 1
	_check(seen > 10 and seen < 120, "con furia 7.5 pica a cuentagotas",
		"%d de 600 lances" % seen)


## El arbol de cañas existe como .tres y escala de verdad: mas sedal, mas
## carrete, mas gracia. La T1 es la base neutra — la caña de siempre.
func _test_rod_tiers_ladder() -> void:
	var tiers: Array[RodTier] = []
	for path in FishingRod.TIER_PATHS:
		var t := load(path) as RodTier
		_check(t != null, "existe " + path)
		if t != null:
			tiers.append(t)
	if tiers.size() != 3:
		return
	_check(tiers[0].line_strength == 1.0 and tiers[0].reel_factor == 1.0
		and tiers[0].snap_hold_bonus == 0.0 and tiers[0].cast_factor == 1.0,
		"la caña de iniciacion es la base neutra")
	_check(tiers[1].line_strength > tiers[0].line_strength
		and tiers[2].line_strength > tiers[1].line_strength,
		"el sedal aguanta mas en cada tier")
	_check(tiers[2].reel_factor > tiers[1].reel_factor
		and tiers[1].reel_factor > 1.0, "y el carrete recoge mas rapido")
	_check(tiers[2].snap_hold_bonus > tiers[1].snap_hold_bonus
		and tiers[1].snap_hold_bonus > 0.0, "y la gracia extra crece")


## La caña de altura aguanta donde la de iniciacion parte: mismo atun, misma
## semilla, misma codicia — solo cambia el aparejo. La puerta blanda medida.
func _test_rod_strengthens_line() -> void:
	var alta := load(FishingRod.TIER_PATHS[2]) as RodTier
	var weak := FightModel.new()
	weak.start(_atun(), _rng(5))
	var strong := FightModel.new()
	strong.start(_atun(), _rng(5), alta)
	for _i in 180: # 3 s de recoger contrando MAL con marejada
		weak.step(1.0 / 60.0, true, weak.pull_dir, 3.0)
		strong.step(1.0 / 60.0, true, strong.pull_dir, 3.0)
	_check(weak.snapped, "la caña de iniciacion parte contra la codicia con atun")
	_check(not strong.snapped, "la de altura aguanta el mismo castigo")
	_check(strong.max_tension() > weak.max_tension(),
		"porque su sedal aguanta de verdad mas tension",
		"%.2f vs %.2f" % [strong.max_tension(), weak.max_tension()])


## Juega una lucha limpia (contrar el tiron, recoger en la pausa) y devuelve
## los segundos hasta que termina como sea.
func _play_clean(m: FightModel) -> float:
	var t: float = 0.0
	while not m.landed and not m.snapped and not m.escaped and t < 60.0:
		var counter := FightModel.Pull.NONE
		if m.pull_dir == FightModel.Pull.LEFT:
			counter = FightModel.Pull.RIGHT
		elif m.pull_dir == FightModel.Pull.RIGHT:
			counter = FightModel.Pull.LEFT
		m.step(1.0 / 60.0, not m.is_pulling(), counter, 1.0)
		t += 1.0 / 60.0
	return t


## Mas carrete = capturas mas rapidas. La promesa central de la mejora ("mas
## peces por salida"), medida con la misma lucha limpia y la misma semilla.
func _test_rod_reels_faster() -> void:
	var alta := load(FishingRod.TIER_PATHS[2]) as RodTier
	var base := FightModel.new()
	base.start(_sardina(), _rng(21))
	var mejor := FightModel.new()
	mejor.start(_sardina(), _rng(21), alta)
	var t_base := _play_clean(base)
	var t_mejor := _play_clean(mejor)
	_check(base.landed and mejor.landed, "ambas cañas terminan la lucha limpia")
	_check(t_mejor <= t_base * 0.9, "la caña de altura captura claramente mas rapido",
		"%.1f s frente a %.1f s" % [t_mejor, t_base])


# =============================================================================
#  El cebo (PESCA.md paso 3)
# =============================================================================

## LA REGLA QUE EL CEBO NO PUEDE ROMPER: compra atencion, no peces que el mar
## no da. Con cebo del mejor y furia de calma NO puede aparecer un pez de otra
## banda — si esto falla, la tesis del juego ("el pez caro vive donde el mar es
## peor") se vende en la lonja y el mar deja de ser el antagonista.
func _test_bait_never_raises_band() -> void:
	var vivo := load("res://resources/cebos/cebo_vivo.tres") as TipoCebo
	_check(vivo != null and vivo.sesgo > 0.0, "el cebo vivo existe y sesga")
	if vivo == null:
		return
	var rng := _rng(4242)
	var intruso := ""
	for _i in 800:
		var s := FishSpecies.choose(1.0, rng, vivo.sesgo)
		if float(s[&"min_fury"]) > 1.0:
			intruso = String(s[&"name"])
	_check(intruso.is_empty(),
		"con cebo del mejor, la calma sigue sin dar peces de otra banda", intruso)

	# Y en banda B tampoco cuela un atun (banda C) por mucho cebo que se eche.
	var alto := 0
	for _i in 800:
		if FishSpecies.tier_of(FishSpecies.choose(5.0, rng, vivo.sesgo)) >= 3:
			alto += 1
	_check(alto == 0, "ni en furia 5 aparece la banda C", "%d colados" % alto)


## Lo que el cebo SI compra: que pique la pieza buena de tu banda en vez de la
## sardina de siempre. Se mide en valor medio de la captura, con la misma
## semilla y la misma furia — solo cambia el cebo.
func _test_bait_biases_to_the_big_one() -> void:
	var vivo := load("res://resources/cebos/cebo_vivo.tres") as TipoCebo
	var comun := load("res://resources/cebos/cebo_comun.tres") as TipoCebo
	if vivo == null or comun == null:
		_check(false, "los dos cebos existen")
		return
	_check(is_zero_approx(comun.sesgo) and comun.espera_factor < 1.0,
		"la masilla solo compra tiempo (sesgo 0, espera mas corta)",
		"sesgo %.2f · espera x%.2f" % [comun.sesgo, comun.espera_factor])
	_check(vivo.espera_factor < comun.espera_factor,
		"y el cebo vivo ademas acorta mas la espera",
		"x%.2f vs x%.2f" % [vivo.espera_factor, comun.espera_factor])

	var sin_cebo: float = _valor_medio(0.0, 4000)
	var con_cebo: float = _valor_medio(vivo.sesgo, 4000)
	_check(con_cebo > sin_cebo * 1.1,
		"el cebo vivo sube claramente el valor medio de lo que pica",
		"%.1f monedas frente a %.1f" % [con_cebo, sin_cebo])


func _valor_medio(sesgo: float, tiradas: int) -> float:
	var rng := _rng(31415)
	var total: float = 0.0
	for _i in tiradas:
		total += float(FishSpecies.choose(4.0, rng, sesgo)[&"value"])
	return total / float(tiradas)


## El cubo y las cargas: cebar coge lo que cabe (ni mas ni menos), el cubo
## descuenta EXACTAMENTE eso, cambiar de cebo tira lo puesto, y cada picada se
## come una carga — pesques o no. Sin esto el cebo no seria una decision.
func _test_bait_charges_and_bucket() -> void:
	var rod: FishingRod = load("res://game/fishing/fishing_rod.tscn").instantiate()
	add_child(rod)
	var cubo: CuboCebo = load("res://game/props/cubo_cebo.tscn").instantiate()
	add_child(cubo)
	await get_tree().process_frame

	var vivo := load("res://resources/cebos/cebo_vivo.tres") as TipoCebo
	_check(rod.cebo_puesto() == null, "la caña arranca a pelo, sin cebo")

	# El fallo silencioso que ya se comio el gancho una vez: una Zona nacida en
	# capa 0 es invisible para la mira del portador, asi que cebar seria
	# imposible EN EL JUEGO aunque todo lo de abajo pase. Sin warning ninguno.
	var zona := cubo.get_node_or_null(^"Zona") as Area3D
	_check(zona != null and zona.collision_layer != 0,
		"la Zona del cubo es visible para la mira del portador")

	var antes: int = cubo.cargas
	_check(cubo.cebar(rod), "E en el cubo ceba la caña")
	_check(rod.cebo_cargas == FishingRod.CEBO_CARGAS_MAX,
		"y llena el anzuelo hasta el tope", "%d" % rod.cebo_cargas)
	_check(cubo.cargas == antes - FishingRod.CEBO_CARGAS_MAX,
		"el cubo descuenta exactamente lo que se llevo",
		"%d -> %d" % [antes, cubo.cargas])
	_check(not cubo.cebar(rod), "cebar con la caña llena no gasta cubo")

	# Cambiar de cebo TIRA lo que quedaba: no se mezclan dos cebos en un anzuelo.
	rod.cebo_cargas = 2
	rod.cebar(vivo, 10)
	_check(rod.cebo == vivo and rod.cebo_cargas == FishingRod.CEBO_CARGAS_MAX,
		"cambiar de cebo tira lo puesto y llena del nuevo", "%d" % rod.cebo_cargas)

	# La picada se come una carga aunque el pez se pierda despues.
	rod.hooked_species = _sardina()
	var cargas_antes: int = rod.cebo_cargas
	rod._start_bite()
	_check(rod.cebo_cargas == cargas_antes - 1,
		"cada picada se come una carga", "%d -> %d" % [cargas_antes, rod.cebo_cargas])

	# Sin cargas, el cebo deja de existir a todos los efectos.
	rod.cebo_cargas = 0
	_check(rod.cebo_puesto() == null and is_zero_approx(rod._cebo_sesgo()),
		"sin cargas la caña vuelve a pescar a pelo")

	# Y un cubo vacio no ceba ni miente en el prompt.
	cubo.cargas = 0
	_check(cubo.vacio() and not cubo.cebar(rod), "el cubo vacio no ceba")

	rod.queue_free()
	cubo.queue_free()
	await get_tree().process_frame


## LA PROMESA DEL SOPORTE DE BORDA (PESCA.md paso 2, PORTEO.md fase B): "clavas
## la caña, achicas o estibas, y vuelves al !". Si la ventana de picada no da
## para cruzar la cubierta, la caña clavada solo sirve para PERDER peces: la
## feature existiria y su promesa no. Se mide contra la geometria REAL del
## barco, asi que agrandarlo o recortar la ventana rompe este test a proposito.
##
## Presupuesto de gestos que NO son correr (reaccion al chomp, soltar lo que
## portas, apuntar al soporte con el rayo del Portador, E + clic). Medido a
## ojo de playtest, deliberadamente conservador.
const GESTOS_SEGUNDOS := 1.0


func _test_staked_bite_window() -> void:
	_check(FishingRod.BITE_WINDOW_SOPORTE > FishingRod.BITE_WINDOW,
		"la caña clavada da mas ventana que la caña en mano",
		"%.1f s vs %.1f s" % [FishingRod.BITE_WINDOW_SOPORTE, FishingRod.BITE_WINDOW])

	var boat: Node3D = load("res://game/boat/fishing_boat.tscn").instantiate()
	add_child(boat)
	await get_tree().process_frame

	var soportes := boat.find_children("*", "SoporteCania", true, false)
	_check(soportes.size() >= 2, "el barco trae soportes en las dos bandas",
		"%d" % soportes.size())

	var player: Player = load("res://game/player/player.tscn").instantiate()
	var walk: float = player.walk_speed
	player.queue_free()

	if soportes.size() >= 2:
		# El peor trayecto util: del soporte de una banda al de la otra.
		var diagonal: float = (soportes[0] as Node3D).global_position.distance_to(
			(soportes[1] as Node3D).global_position)
		var necesario: float = GESTOS_SEGUNDOS + diagonal / maxf(walk, 0.001)
		_check(FishingRod.BITE_WINDOW_SOPORTE >= necesario,
			"y esa ventana cubre cruzar la cubierta y retomarla",
			"ventana %.1f s frente a %.1f s necesarios (%.2f m a %.1f m/s)" % [
				FishingRod.BITE_WINDOW_SOPORTE, necesario, diagonal, walk])
		# El fallo que motivo el cambio: con la ventana de mano no se llegaba.
		_check(FishingRod.BITE_WINDOW < necesario,
			"(y con la ventana de mano NO se llegaba: por eso existe la larga)",
			"%.1f s frente a %.1f s" % [FishingRod.BITE_WINDOW, necesario])

	# Y la caña elige la ventana por DONDE esta, no por quien pregunta.
	var rod: FishingRod = load("res://game/fishing/fishing_rod.tscn").instantiate()
	add_child(rod)
	await get_tree().process_frame
	rod.hooked_species = _sardina()
	rod._start_bite()
	var en_mano: float = rod._bite_left
	rod.soporte = soportes[0] if not soportes.is_empty() else Node3D.new()
	rod._start_bite()
	_check(is_equal_approx(en_mano, FishingRod.BITE_WINDOW)
		and is_equal_approx(rod._bite_left, FishingRod.BITE_WINDOW_SOPORTE),
		"la ventana la decide donde esta la caña, no quien pregunta",
		"mano %.1f s · clavada %.1f s" % [en_mano, rod._bite_left])
	rod.queue_free()
	boat.queue_free()
	await get_tree().process_frame


## El pez fisico: masa real, escala por peso, y FLOTA si cae al agua.
func _test_fish_body() -> void:
	Ocean.set_fury_immediate(0.0)
	var fish: Fish = load("res://game/fishing/fish.tscn").instantiate()
	add_child(fish)
	fish.setup(_atun())
	fish.global_position = Vector3(50, 2, 50)

	_check(fish.mass == 60.0, "el atun pesa 60 kg de verdad", "%.0f" % fish.mass)
	_check(fish.species_name == "Atun" and fish.value == 450, "especie y valor")

	for _i in 500:
		await get_tree().physics_frame
	var y := fish.global_position.y
	_check(is_finite(y) and absf(y) < 2.0, "el pez flota en vez de hundirse o volar",
		"y=%.2f" % y)
	fish.queue_free()


## Cableado: el pescador esta montado, en primera persona solo se le ve un brazo
## (ni cuerpo ni cuello), la caña cuelga de la camara con su escena de pez
## asignada, y las manos ocupadas bloquean el movimiento de verdad.
func _test_wiring() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var player := scene.get_node(^"Player") as Player
	var model := player.get_node_or_null(^"Pescador")
	_check(model != null, "el pescador esta montado en el jugador")
	if model != null:
		var solo_sombra := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var body_meshes := model.find_children("*", "MeshInstance3D", true, false)
		_check(not body_meshes.is_empty(), "el pescador conserva geometria dibujable")
		var drawn: Array[String] = []
		for mesh: MeshInstance3D in body_meshes:
			if mesh.visible and mesh.cast_shadow != solo_sombra:
				drawn.append(mesh.name)
		_check(drawn.is_empty(), "no se dibuja ni una pieza del cuerpo en primera persona",
			"se dibujan: %s" % ", ".join(drawn))
		var proyectan_sombra := true
		for mesh: MeshInstance3D in body_meshes:
			proyectan_sombra = proyectan_sombra and mesh.cast_shadow == solo_sombra
		_check(proyectan_sombra,
			"cuerpo, cuello y cara siguen proyectando sombra en cubierta")

		_check(player.arm != null, "el brazo del viewmodel existe")
		if player.arm != null:
			_check(player.arm.visible and player.arm.is_inside_tree(), "y se dibuja")
			_check(player.arm.get_parent() != null and player.arm.get_parent().name == "RodPivot",
				"colgado del mango de la caña, no de la camara")
			var bulto := player.arm.mesh.get_aabb().size * player.arm.scale
			_check(bulto.y > bulto.x * 2.5, "y es un brazo, no un muñon",
				"%.2f m de largo por %.2f de ancho" % [bulto.y, bulto.x])

		# El toggle de tercera persona (capturas y, manana, los demas jugadores).
		player.set_body_visible(true)
		var cuerpo_visible := true
		for mesh: MeshInstance3D in body_meshes:
			cuerpo_visible = cuerpo_visible and (
				mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		_check(cuerpo_visible, "en tercera persona vuelve el cuerpo entero")
		_check(player.arm != null and not player.arm.visible,
			"y se apaga el brazo del viewmodel")
		player.set_body_visible(false)

	var rod := player.get_node_or_null(^"Camera3D/FishingRod") as FishingRod
	_check(rod != null, "la caña cuelga de la camara")
	if rod != null:
		_check(rod.fish_scene != null, "con su escena de pez asignada")
		_check(rod.tier != null and rod.tier.tier_name != "",
			"y un tier de aparejo montado de serie")
		_check(rod.get_node_or_null(^"RodPivot/Tip") != null, "y su punta para el sedal")
		_check_arte_cania(rod)
		# El otro fallo mudo del latigazo: que el asset cargue pero nadie lo
		# cablee. Cuelga del pivote para que salga de la caña, no de la camara.
		_check(rod._cast_p != null and rod._cast_p.stream == SfxLibrary.cast_whip
			and rod._cast_p.get_parent() == rod.get_node(^"RodPivot"),
			"con el latigazo cableado en la caña")
		# La cama de recogida es top_level: si no, seguiria a la camara y el
		# forcejeo dejaria de venir de donde esta el pez.
		_check(rod._haul_p != null and rod._haul_p.stream == SfxLibrary.haul_loop
			and rod._haul_p.top_level and rod._haul_p.volume_db < -50.0,
			"y la cama de recogida cableada, muda y en el mundo")

	player.hands_busy = true
	_check(player._input_direction() == Vector3.ZERO,
		"con las manos ocupadas no se puede andar")
	player.hands_busy = false

	var hud := scene.get_node(^"OceanDebugHUD")
	_check(hud.get_node_or_null(hud.rod_path) != null, "el HUD encuentra la caña")

	scene.queue_free()
	await get_tree().process_frame


## El arte de la caña es un GLB (`tools/build_fishing_rod.py`), y cambiar de
## primitivas a modelo abrio tres fallos que NO gritan:
##
## 1. Que el GLB no cargue o cambie de sitio: la caña sale invisible y el juego
##    sigue funcionando perfectamente, lanzando desde la nada.
## 2. Que la punta del cuerpo se despegue del nodo `Tip`: el sedal nace en el
##    aire, unos centimetros por delante o por detras de la caña.
## 3. Que la malla `Grip` se renombre al reconstruir el modelo: `_apply_tier`
##    no encuentra a quien tintar, sale por el `return` y el color del aparejo
##    deja de verse sin un solo error en consola.
func _check_arte_cania(rod: FishingRod) -> void:
	var cania := rod.get_node_or_null(^"RodPivot/Cania") as Node3D
	_check(cania != null, "con el modelo de caña colgando del pivote")
	if cania == null:
		return
	var piezas := {}
	for m: MeshInstance3D in cania.find_children("*", "MeshInstance3D", true, false):
		piezas[m.name] = m
	_check(piezas.has("Blank") and piezas.has("Guides") and piezas.has("ReelRotor"),
		"con cuerpo, anillas y carrete")

	var blank := piezas.get("Blank") as MeshInstance3D
	if blank != null:
		var caja := blank.get_aabb()
		var pivote := rod.get_node(^"RodPivot") as Node3D
		var punta_y: float = pivote.to_local(blank.to_global(caja.position + caja.size)).y
		var tip_y: float = (rod.get_node(^"RodPivot/Tip") as Node3D).position.y
		_check(absf(punta_y - tip_y) < 0.02,
			"y el sedal naciendo en la punta de verdad (%.3f vs %.3f)" % [punta_y, tip_y])

	var grip := piezas.get("Grip") as MeshInstance3D
	_check(grip != null, "y la pieza que lleva el color del tier")
	if grip == null:
		return
	var tier_previo := rod.tier
	var altura := load("res://resources/rod_tiers/tier_3_altura.tres") as RodTier
	rod.tier = altura
	rod._apply_tier()
	var mat := grip.get_surface_override_material(0) as StandardMaterial3D
	_check(mat != null and mat.albedo_color.is_equal_approx(altura.accent_color),
		"que de verdad cambia al montar otro aparejo")
	rod.tier = tier_previo
	rod._apply_tier()

	# El carrete es la unica pieza MOVIL de la caña. Si el GLB deja de traer sus
	# ejes de giro (o alguien los renombra al reconstruir el modelo), se queda
	# quieto mientras el jugador spamea el clic: cero errores, y la sensacion de
	# que el juego no le esta oyendo.
	_check(rod._rotor != null and rod._handle != null,
		"y el carrete con sus dos piezas moviles")
	if rod._rotor == null or rod._handle == null:
		return
	var pose_rotor := rod._rotor.transform.basis
	var pose_manivela := rod._handle.transform.basis
	var estado_previo := rod.state
	rod.state = FishingRod.State.FIGHT
	rod._reeling = true
	rod._spin_reel(0.02)
	var giro_manivela: float = pose_manivela.get_rotation_quaternion().angle_to(
		rod._handle.transform.basis.get_rotation_quaternion())
	var giro_rotor: float = pose_rotor.get_rotation_quaternion().angle_to(
		rod._rotor.transform.basis.get_rotation_quaternion())
	_check(giro_manivela > 0.05 and giro_rotor > giro_manivela * 2.0,
		"que gira al recoger, y el rotor mucho mas que la manivela")
	rod._reeling = false
	rod.state = estado_previo
	rod._reel_angle = 0.0
	rod._rotor.transform.basis = pose_rotor
	rod._handle.transform.basis = pose_manivela

	# El doblez: el cuerpo se CURVA y la punta se va con el. Si el rig no llegara
	# (modelo viejo, huesos renombrados), la caña volveria a inclinarse tiesa sin
	# decir nada, y el sedal seguiria saliendo de un punto que ya no es la punta.
	_check(rod._skel != null and rod._huesos.size() == FishingRod.BEND_BONE_WEIGHTS.size(),
		"y el rig que curva el cuerpo al pelear")
	if rod._skel == null:
		return
	rod._aplicar_doblez(0.0)
	var punta_recta := rod._tip.position
	rod._aplicar_doblez(0.8)
	var punta_curva := rod._tip.position
	rod._aplicar_doblez(0.0)
	_check(punta_curva.distance_to(punta_recta) > 0.05
		and punta_curva.y < punta_recta.y and punta_curva.z < punta_recta.z,
		"y que arrastra con el el punto donde nace el sedal")


# =============================================================================
#  Game feel
# =============================================================================

## La fabrica de sonidos: todo generado, formato correcto, y el loop de buzz
## con su bucle cerrado (es el sustituto del scheduler a alta tasa).
func _test_sfx_library() -> void:
	_check(SfxLibrary.reel_clicks.size() >= 4, "hay variantes de click de carrete",
		"%d" % SfxLibrary.reel_clicks.size())
	var all_ok := true
	var pools: Array = [SfxLibrary.reel_clicks, SfxLibrary.creak_pulses,
		SfxLibrary.splashes, SfxLibrary.jingles,
		[SfxLibrary.plip, SfxLibrary.chomp, SfxLibrary.snap, SfxLibrary.thud,
		SfxLibrary.lap, SfxLibrary.reel_buzz]]
	for pool in pools:
		for wav in pool:
			var w := wav as AudioStreamWAV
			if w == null or w.data.is_empty() or w.mix_rate != SfxLibrary.RATE 					or w.format != AudioStreamWAV.FORMAT_16_BITS:
				all_ok = false
	_check(all_ok, "todos los sonidos generados en 16 bits a 22050 Hz")
	_check(SfxLibrary.reel_buzz.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and SfxLibrary.reel_buzz.loop_end > 0, "el buzz es un loop cerrado")
	# El latigazo es el primer sample HORNEADO de la caña (regla 10). Si alguien
	# lo renombra, lo mueve o el .import se pierde, `load()` devuelve null y el
	# lanzamiento se queda mudo sin un solo error: exactamente el fallo
	# silencioso que este arnes existe para cazar.
	var whip := SfxLibrary.cast_whip
	_check(whip != null and not whip.data.is_empty(), "el latigazo esta cargado")
	if whip != null:
		_check(whip.get_length() > 0.2 and whip.get_length() < 0.6,
			"el latigazo dura lo de un gesto (~0.4 s)", "%.2f s" % whip.get_length())
		# Mono a proposito: el render es dual-mono y el player 3D lo colapsaria
		# igual. Si vuelve estereo es que el .import se reimporto con defaults.
		_check(not whip.stereo and whip.mix_rate == 48000,
			"el latigazo entra mono a 48 kHz", "%d Hz" % whip.mix_rate)

	# La cama de recogida sin loop se cortaria a los 9,5 s de lucha larga y
	# nadie veria un error: el .import es quien lo fuerza (el .wav no trae
	# chunk `smpl` que detectar), asi que se comprueba aqui.
	var haul := SfxLibrary.haul_loop
	_check(haul != null and not haul.data.is_empty(), "la cama de recogida esta cargada")
	if haul != null:
		_check(haul.loop_mode == AudioStreamWAV.LOOP_FORWARD and haul.loop_end > 0,
			"y es un loop cerrado hacia adelante")
		_check(not haul.stereo and haul.mix_rate == 48000 and haul.get_length() > 5.0,
			"mono a 48 kHz y larga (no se delata al repetirse)",
			"%.1f s" % haul.get_length())
	_check(FishingRod.HAUL_DB < -4.0,
		"y entra por debajo del tren de clicks, que es quien lleva la tension",
		"%.1f dB" % FishingRod.HAUL_DB)

	_check(SfxLibrary.jingles.size() == 3
		and SfxLibrary.jingles[2].data.size() > SfxLibrary.jingles[0].data.size(),
		"3 jingles y el epico dura mas que el comun")

	# La curva del click train: silencio = vas bien; el maximo ronda 22 Hz.
	_check(SfxLibrary.click_rate_for(0.2) == 0.0, "bajo 30% de tension, silencio")
	_check(SfxLibrary.click_rate_for(0.5) > 3.0, "a media tension, clicks")
	var top := SfxLibrary.click_rate_for(1.0)
	_check(absf(top - 22.0) < 0.5, "a tension maxima ~22 Hz", "%.1f" % top)

	_check(AudioServer.get_bus_index("Reel") != -1 and AudioServer.get_bus_index("SFX") != -1,
		"los buses Reel y SFX existen")


## El plan de nibbles: 1-4 toques falsos, separados 0.5-1.5 s. Tras el ultimo,
## el mordisco esta garantizado (eso lo hace la maquina de estados).
func _test_nibble_plan() -> void:
	var rng := _rng(77)
	var ok := true
	for _i in 200:
		var plan := FishingRod.plan_nibbles(rng)
		if plan.size() < 1 or plan.size() > 4:
			ok = false
		for d in plan:
			if d < 0.5 or d > 1.5:
				ok = false
	_check(ok, "el plan de nibbles respeta 1-4 toques de 0.5-1.5 s")


## La camara: el trauma decae solo, el FOV vuelve a su base, y nada rota jamas.
func _test_camera_feedback() -> void:
	var cam := CameraFeedback.new()
	cam.fov = 78.0
	add_child(cam)
	await get_tree().process_frame

	var base_rot := cam.rotation
	cam.add_trauma(0.6)
	var moved := false
	for _i in 20:
		await get_tree().process_frame
		if cam.position.length() > 0.001:
			moved = true
	_check(moved, "el trauma mueve la camara (traslacion)")
	_check(cam.rotation == base_rot, "y JAMAS la rota (regla anti-mareo)")

	for _i in 60:
		await get_tree().process_frame
	_check(cam.position.length() < 0.002, "el trauma decae solo",
		"offset %.4f" % cam.position.length())

	cam.kick_fov(4.0, 0.05, 0.0, 0.1)
	await get_tree().create_timer(0.08).timeout
	var kicked: float = cam.fov
	await get_tree().create_timer(0.4).timeout
	_check(kicked > 78.5, "el kick de FOV empuja", "%.1f" % kicked)
	_check(absf(cam.fov - 78.0) < 0.2, "y vuelve solo a la base", "%.1f" % cam.fov)

	cam.kick_fov(20.0, 0.01, 0.0, 0.01)
	await get_tree().create_timer(0.05).timeout
	_check(cam.fov <= 83.1, "el tope duro de +-5 grados aguanta", "%.1f" % cam.fov)

	cam.queue_free()
	await get_tree().process_frame


## La UI de pesca del playtest: "!" al picar, flecha con la tecla correcta en
## la lucha, RECOGE en la pausa, y resultados con su color.
func _test_fishing_hud() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var rod := scene.get_node(^"Player/Camera3D/FishingRod") as FishingRod
	var hud: FishingHud = rod._hud
	_check(hud != null, "la caña tiene HUD de pesca")
	if hud == null:
		scene.queue_free()
		return

	hud.show_bite()
	_check(hud._bite_mark.visible, "al picar aparece el ! en pantalla")

	hud.on_hooked()
	_check(not hud._bite_mark.visible and hud._fight_box.visible,
		"al clavar el ! se va y entra el panel de lucha")

	# El pez tira a la IZQUIERDA -> la flecha pide D (->).
	hud.update_fight(FightModel.Pull.LEFT, false, 0.4, 0.5, false, false)
	_check(hud._arrow.visible and hud._arrow.text.contains("D"),
		"pez tirando IZQ pide la tecla D", hud._arrow.text)
	hud.update_fight(FightModel.Pull.RIGHT, false, 0.4, 0.5, false, false)
	_check(hud._arrow.text.contains("A"), "pez tirando DER pide la tecla A")

	# En la pausa: RECOGE; con el anzuelo soltandose: RECOGE YA.
	hud.update_fight(FightModel.Pull.NONE, true, 0.1, 0.5, false, false)
	_check(not hud._arrow.visible and hud._action.text.contains("RECOGE"),
		"la pausa pide RECOGER")
	hud.update_fight(FightModel.Pull.NONE, true, 0.1, 0.5, true, false)
	_check(hud._action.text.contains("SE SUELTA"), "el aviso de escupida grita")

	# Tension critica mientras recoges: SUELTA en rojo.
	hud.update_fight(FightModel.Pull.LEFT, false, 0.9, 0.5, false, true)
	_check(hud._action.text.contains("SUELTA"), "la tension critica pide SOLTAR")

	# Resultado: aparece y se desvanece solo.
	hud.show_result("¡Bacalao · 12 kg!", Color.GOLD)
	_check(hud._result.visible and not hud._fight_box.visible,
		"el resultado se planta y la lucha se esconde")
	await get_tree().create_timer(2.3).timeout
	_check(not hud._result.visible, "y se desvanece solo")

	scene.queue_free()
	await get_tree().process_frame


## El acompañamiento del forcejeo: A tira a la izquierda, D a la derecha, el
## pez arrastra hacia su lado, y LA CONTRA CORRECTA CENTRA LA CAÑA — la caña
## quieta es la señal de que aguantas bien.
func _test_lean_accompaniment() -> void:
	_check(FishingRod.lean_target_for(FightModel.Pull.NONE, true, false, 0.5) > 0.1,
		"A tira la caña a la izquierda")
	_check(FishingRod.lean_target_for(FightModel.Pull.NONE, false, true, 0.5) < -0.1,
		"D a la derecha")

	var free := FishingRod.lean_target_for(FightModel.Pull.LEFT, false, false, 0.5)
	_check(free > 0.15, "el pez sin contra arrastra la caña a su lado",
		"%.2f" % free)
	var countered := FishingRod.lean_target_for(FightModel.Pull.LEFT, false, true, 0.5)
	_check(absf(countered) < 0.1, "la contra correcta centra la caña",
		"%.2f" % countered)
	var wrong := FishingRod.lean_target_for(FightModel.Pull.LEFT, true, false, 0.5)
	_check(wrong > free, "contrar MAL exagera el bandazo — el error se ve gordo",
		"%.2f vs %.2f" % [wrong, free])


## El arrastre de camara del pez escapandose: traslacional, con tope duro, se
## suelta solo, y JAMAS rota (la regla anti-mareo cubre tambien esto).
func _test_camera_drag() -> void:
	var cam := CameraFeedback.new()
	add_child(cam)
	await get_tree().process_frame
	var base_rot := cam.rotation

	cam.set_drag(Vector2(0.2, 0.0)) # pide 20 cm: el tope debe recortarlo
	for _i in 30:
		await get_tree().process_frame
	_check(cam.position.x > 0.02, "el arrastre tira de la camara",
		"x=%.3f" % cam.position.x)
	_check(cam.position.length() <= 0.05, "con tope duro de 4.5 cm",
		"%.3f" % cam.position.length())
	_check(cam.rotation == base_rot, "y sin rotar jamas")

	cam.set_drag(Vector2.ZERO)
	for _i in 100:
		await get_tree().process_frame
	_check(cam.position.length() < 0.004, "y se suelta solo al soltar el pez",
		"%.4f" % cam.position.length())

	cam.queue_free()
	await get_tree().process_frame
