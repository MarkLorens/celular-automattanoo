# Node2D rather than Node: the level is one, and dropping nutrients needs the
# canvas transform that get_global_mouse_position() reads.
extends Node2D

@export var colonies: Array[CellColony] = []
## The world boundary. Every colony's leash is derived from it.
@export var dish: PetriDish
## Panning gets clamped to the dish, so you can never scroll off into the void.
@export var camera: Camera2D
## Dropped at the cursor on the "spawn_nutrient" action.
@export var nutrient_scene: PackedScene

@export_group("Abilities")
## Every cursor-spawn ability shares one shape: locked until some seconds of play
## have passed, then usable on its own cooldown, dropping its thing at the mouse.
## The nutrient is configured here; each colony that names a summon_action adds
## another, built from the colony's own summon fields.
## Seconds of play before the nutrient drop unlocks.
@export var nutrient_unlock_at: float = 80.0
## Seconds between nutrient drops once unlocked. Also the real cap on how fast
## flockers can breed, since a nutrient is what buys a new one.
@export var nutrient_cooldown: float = 30.0

@export_group("Temperature")
## The gauge the player drags. Its 0..1 fill is read as a temperature between
## the two below.
@export var temperature_gauge: ArcMeter
@export var min_celsius: float = 0.0
@export var max_celsius: float = 100.0
@export var gauge_spawn_timing: float = 40.0

@export_group("Lighting")
## Where the lamp hangs over the dish. Every shadow slides away from it.
@export var light_position: Vector2 = Vector2.ZERO
## Constant drop every shadow gets, so something sitting directly under the lamp
## still has one instead of looking pasted flat to the glass.
@export var shadow_base_offset: Vector2 = Vector2(18.0, 24.0)
## Extra slide per unit of distance from the lamp, which fans the shadows out
## across the dish. 0 points every shadow the same way, like a distant sun.
@export var shadow_falloff: float = 0.012
## Cap, so cells out at the rim do not trail absurd shadows.
@export var shadow_max_offset: float = 45.0

# UI stuff
@onready var HUD := $HUD
@onready var game_timer := $HUD/GameTimer
@onready var game_over_screen := $UI/GameOverScreen
# The four crossfading heat beds. Softly fetched so the level still runs without
# them, and null-checked at every call site below.
@onready var _temp_ambience: TemperatureAmbience = get_node_or_null(^"TemperatureAmbience")
# Instruction pills off the right of the dish, one per ability. Fetched softly so
# a level that has not laid them all out yet still runs. Their locked/greyed state
# is driven from _process against the same unlock clock the abilities use.
@onready var _capsules: Array = [
	get_node_or_null(^"HUD/CapsuleZ"),
	get_node_or_null(^"HUD/CapsuleX"),
	get_node_or_null(^"HUD/CapsuleC"),
]
# Owns the pause key, on its own node so it keeps hearing input while the tree is
# frozen. Softly fetched like everything else here, so a level laid out without
# one still runs -- it simply cannot be paused.
@onready var _pause_key: Node = get_node_or_null(^"PauseKey")

## Fires whenever the player moves the gauge. The dish temperature in celsius.
signal temperature_changed(celsius: float)

## Current dish temperature. Read-only from outside -- the gauge drives it.
var temperature: float = 0.0

# A cursor-spawn ability: locked until unlock_at seconds of play, then usable
# whenever ready_in has counted back down to 0. `spawn` takes the drop position.
class SpawnAbility extends RefCounted:
	var action: StringName
	var unlock_at: float
	var cooldown: float
	var spawn: Callable
	var ready_in: float = 0.0

	func _init(a: StringName, unlock: float, cd: float, s: Callable) -> void:
		action = a
		unlock_at = unlock
		cooldown = cd
		spawn = s

# Built once in _ready from the nutrient plus every summonable colony.
var _abilities: Array = []
# action -> the ability itself, so a capsule can be driven from whichever one it
# illustrates -- when it unlocks and how far through its cooldown it is -- without
# the pills having to hold references back to abilities they know nothing about.
var _ability_by_action: Dictionary = {}
# Seconds of actual play. _process only ticks while unpaused, so this never
# advances behind the title card or the end screen -- it is gameplay time, which
# is what the ability unlocks are measured in. It doubles as the test for whether
# a run has begun at all, which is what the pause key reads.
var _elapsed: float = 0.0
# Set once the run has ended, so it can only end once and so the pause key knows
# there is nothing left to pause.
var _over: bool = false

# Index-aligned with colonies: each species grows on its own clock.
var _time_until_spawn: Array[float] = []
# Index-aligned too: what each colony has alive, so a capped one can tell
# whether it has room. Entries go stale as cells are eaten and get pruned on
# read, which is cheaper than wiring a signal to every cell just to count them.
var _alive: Array[Array] = []

func _ready() -> void:
	_resolve_scene_refs()
	_wire_temperature()
	_apply_shadow_lighting()
	_fit_camera_to_dish()
	_reveal_gauge_later()
	_build_abilities()
	if _pause_key != null:
		_pause_key.pressed.connect(_toggle_pause)
	# Idempotent: coming in from the menu the track is already playing and this
	# leaves it untouched; after a retry it brings the stopped track back.
	Audio.play_music()
	for i in colonies.size():
		var colony: CellColony = colonies[i]
		_time_until_spawn.append(_first_delay_for(colony))
		_alive.append([])
		if colony == null:
			continue
		for n in colony.count:
			if _at_cap(i):
				break  # count overshooting max_population is the cap's problem.
			_spawn_cell(i)

	# Boot frozen behind the title card. The dish is fully set up and rendered but
	# nothing moves; the start screen (which runs while paused) lifts this the
	# moment the player presses to begin, and every clock starts from here.
	get_tree().paused = true

## The nutrient plus one summon per colony that asked for one. Nutrients drop a
## plain scene; a summon reuses the colony's own _spawn_cell, so a summoned cell
## is set up exactly like a drip-fed one -- same leash, same random texture, same
## population bookkeeping -- only placed at the cursor instead of on the clock.
func _build_abilities() -> void:
	_abilities.append(
		SpawnAbility.new(&"spawn_nutrient", nutrient_unlock_at, nutrient_cooldown, _spawn_nutrient))
	for i in colonies.size():
		var colony: CellColony = colonies[i]
		if colony == null or colony.summon_action == &"":
			continue
		# A per-iteration copy: the lambda captures it by value, so each summon
		# keeps its own index rather than sharing the loop's final one.
		var index: int = i
		_abilities.append(SpawnAbility.new(
			colony.summon_action,
			colony.summon_unlock_at,
			colony.summon_cooldown,
			func(at: Vector2) -> void: _spawn_cell(index, at)))
	for ability in _abilities:
		_ability_by_action[ability.action] = ability

## Keeps the gauge hidden and untouchable until the dish has had time to settle.
##
## The wait lives in its own function rather than in _ready() on purpose. `await`
## suspends whatever function it sits in, so an await partway through _ready()
## stops everything below it from running until the timer fires -- which put the
## entire colony setup behind the delay. _time_until_spawn and _alive stayed
## empty while _process was already indexing them, giving an out-of-bounds error
## every single frame and not one cell spawned for the whole wait.
##
## Called without awaiting it, this runs as far as its own await and hands
## control straight back, so _ready() carries on as normal.
func _reveal_gauge_later() -> void:
	if temperature_gauge == null or gauge_spawn_timing <= 0.0:
		return
	# Greyed and inert rather than hidden: an unearned gauge stays in its spot,
	# plainly switched off, matching how the ability capsules read while locked.
	temperature_gauge.set_locked(true)
	# process_always = false so the wait counts real play time only: the clock is
	# started during boot but holds while the title card has the game paused, and
	# resumes once the player begins. Otherwise it would tick down behind the card.
	await get_tree().create_timer(gauge_spawn_timing, false).timeout
	if not is_instance_valid(temperature_gauge):
		return  # Level torn down while the timer was running.
	temperature_gauge.set_locked(false)

## How long this colony waits for its first drip-fed cell. Only the opening wait
## differs; every spawn after it is spawn_interval apart, which is why the timer
## is reset from the interval rather than from here once it has fired.
func _first_delay_for(colony: CellColony) -> float:
	if colony == null:
		return 0.0
	if colony.first_spawn_delay >= 0.0:
		return colony.first_spawn_delay
	return colony.spawn_interval

## Shadows read the lamp off statics, so the whole dish agrees on one light
## without every cell having to carry a reference to it. Set before anything
## spawns, or the first batch drops its shadows using the built-in defaults.
func _apply_shadow_lighting() -> void:
	DropShadow.light_position = light_position
	DropShadow.base_offset = shadow_base_offset
	DropShadow.falloff = shadow_falloff
	DropShadow.max_offset = shadow_max_offset

## The exported node references may not survive the scene file: without
## PROPERTY_USAGE_NODE_PATH_FROM_SCENE_ROOT on the property, the stored
## NodePath("PetriDish") is never turned into a node and `dish` simply loads
## null -- which silently disables the camera fit, every colony's leash and the
## nutrient clamp, since all three check for null and give up quietly.
##
## Falling back to the conventional child names is the safety net. An export
## that does arrive populated still wins.
func _resolve_scene_refs() -> void:
	if dish == null:
		dish = get_node_or_null(^"PetriDish") as PetriDish
	if camera == null:
		camera = get_node_or_null(^"Camera2D") as Camera2D
	if temperature_gauge == null:
		temperature_gauge = get_node_or_null(^"HUD/TemperatureGauge") as ArcMeter

## The gauge is a plain slider that knows nothing about degrees; turning its fill
## into a temperature is the level's job. Read once at startup too, so a gauge
## saved part-filled starts the dish at the matching heat rather than at zero.
func _wire_temperature() -> void:
	# Pushed even with no gauge present, because Cell.dish_celsius is a static
	# that outlives a scene reload and would otherwise start at the last run's
	# reading rather than this one's.
	_on_gauge_moved(temperature_gauge.value if temperature_gauge != null else 0.0)
	if temperature_gauge != null:
		temperature_gauge.value_changed.connect(_on_gauge_moved)

func _on_gauge_moved(value: float) -> void:
	temperature = lerpf(min_celsius, max_celsius, value)
	Cell.dish_celsius = temperature
	if dish != null:
		dish.temperature = temperature
	if _temp_ambience != null:
		_temp_ambience.set_temperature(temperature)
	temperature_changed.emit(temperature)

## Whether the dish is currently too hot for this colony to drip-feed. Says
## nothing about breeding: a flocker eating a nutrient still splits at 90
## degrees, which is the whole point of the rule.
func _too_hot_for(colony: CellColony) -> bool:
	return temperature >= colony.halts_at_celsius

## _unhandled_input rather than _input, so anything the game grows later -- a
## menu, a HUD button -- gets first refusal on the key. is_action_pressed()
## ignores echoes by default, so holding the key spawns one thing, not a stream.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("force_end_game"):
		game_over()
		return
	for ability in _abilities:
		if event.is_action_pressed(ability.action):
			_try_use_ability(ability)
			return

## Fires an ability if it is both unlocked and off cooldown. A press that is too
## early or too soon is simply refused, not queued -- the same way the nutrient
## has always ignored a mistimed key.
func _try_use_ability(ability: SpawnAbility) -> void:
	if _elapsed < ability.unlock_at:
		return  # Still locked -- not enough play time yet.
	if ability.ready_in > 0.0:
		return  # Still cooling down.
	ability.spawn.call(get_global_mouse_position())
	ability.ready_in = ability.cooldown
	get_viewport().set_input_as_handled()

## Holds the run and lets it go again -- but only a run that is actually under
## way. The tree is paused behind the title card and behind the end screen too,
## and lifting either of those with the pause key would drop the player into a
## game they had not started, or back into one that was already finished.
##
## _elapsed is what tells them apart: it only advances on unpaused frames, so a
## zero reading means the title card is still up and nothing has begun.
func _toggle_pause() -> void:
	if _over or _elapsed <= 0.0:
		return
	get_tree().paused = not get_tree().paused


## Ends the run. Idempotent, and it has to be: three separate things call for the
## end now -- the quit key, and either side of the dish dying out -- and the
## census in particular would otherwise ask for it again every frame.
func game_over() -> void:
	if _over:
		return
	_over = true
	game_timer.stop()

	# Freeze the dish behind the end screen. Pausing the tree stops every cell,
	# spawn clock and the timer itself in one move; the end screen keeps running
	# because its process_mode is set to run while paused, so Restart still works.
	get_tree().paused = true

	# The run is over, so its sound stops with it: the music (which otherwise plays
	# on unbroken) and the heat beds both fall silent behind the end screen.
	Audio.stop_music()
	if _temp_ambience != null:
		_temp_ambience.stop()

	HUD.hide()
	game_over_screen.show_result(game_timer.final_time)

func _spawn_nutrient(at: Vector2) -> void:
	if nutrient_scene == null:
		push_warning("Level has no nutrient_scene assigned; nothing to drop.")
		return
	var nutrient: Node2D = nutrient_scene.instantiate()
	add_child(nutrient)
	# Positioned after parenting so the drop lands under the cursor whatever
	# transform the level itself happens to carry.
	nutrient.global_position = _clamped_to_dish(at)

## Nearest point inside the dish. Clamped to the leash radius rather than the
## glass itself, so food can never land in the margin the cells are turned back
## from and sit there unreachable.
func _clamped_to_dish(point: Vector2) -> Vector2:
	if dish == null:
		return point
	var centre: Vector2 = dish.global_position
	var limit: Vector2 = dish.leash_radii()
	var normalized: Vector2 = (point - centre) / limit
	if normalized.length() <= 1.0:
		return point
	return centre + normalized.normalized() * limit

func _process(delta: float) -> void:
	_elapsed += delta
	for ability in _abilities:
		ability.ready_in = maxf(ability.ready_in - delta, 0.0)

	# Grey each pill until its ability's unlock time has been reached, and drain
	# the recharge pane down as its cooldown runs off. set_locked is a no-op
	# unless the state actually flips, so this is cheap every frame.
	for capsule in _capsules:
		if capsule == null:
			continue
		var ability: SpawnAbility = _ability_by_action.get(capsule.action)
		if ability == null:
			# A pill naming an action no level ability answers to. Left plain and
			# available rather than dark, so a mis-wired capsule reads as the
			# oversight it is instead of as an ability that never unlocks.
			capsule.set_locked(false)
			capsule.set_cooldown(0.0)
			continue
		capsule.set_locked(_elapsed < ability.unlock_at)
		# An ability with no cooldown is never recharging, and asking how far
		# through a zero-length wait it is would divide by zero.
		capsule.set_cooldown(ability.ready_in / ability.cooldown if ability.cooldown > 0.0 else 0.0)

	for i in colonies.size():
		var colony: CellColony = colonies[i]
		if colony == null or colony.spawn_interval <= 0.0:
			continue
		# A colony that cannot spawn parks its timer at full rather than burning
		# it down against a spawn that cannot happen -- whether it is at its
		# population cap or the dish has been cooked past its limit. Either way
		# the block lifting is followed by a whole interval, instead of by
		# whatever happened to be left on a clock that ran while it was stuck.
		if _at_cap(i) or _too_hot_for(colony):
			_time_until_spawn[i] = colony.spawn_interval
			continue
		# Run down at whatever pace the colony is currently breeding at rather
		# than in real seconds, so a species that thrives on something -- the
		# cold, a nutrient just eaten -- fills the dish faster while it lasts.
		_time_until_spawn[i] -= delta * _breeding_rate(i)
		if _time_until_spawn[i] <= 0.0:
			_time_until_spawn[i] = colony.spawn_interval
			_spawn_cell(i)

	# Last, so this frame's arrivals are counted before the dish is judged on
	# them -- a colony re-seeding on the very frame the last of it was eaten
	# should not read as a side that has died out.
	_check_ecosystem_collapse()

## Ends the run the instant the dish stops being an ecosystem: one side eaten out
## or died off, leaving only predators or only prey. An empty dish is neither of
## those -- nothing is "left" in it at all -- and the drip feeds will refill it,
## so that one is allowed to run on.
func _check_ecosystem_collapse() -> void:
	var census: Vector2i = _census()
	if census.x == 0 and census.y == 0:
		return
	if census.x == 0 or census.y == 0:
		game_over()

## The dish's census: predators in x, prey in y, counting only what is genuinely
## still swimming.
##
## The eaten are skipped by hand, and that is the load-bearing part. queue_free()
## does not take a node out of its groups until the end of the frame, so the cell
## a predator claimed this frame is still listed -- and it is exactly the frame
## the last one goes that this exists to catch, so counting it would hide the
## very instant being watched for.
##
## A predator is never counted as prey, even were some future species tagged as
## both. is_edible() takes the same care for the same reason: one cell answering
## on both sides could hold a collapsed dish open on its own.
func _census() -> Vector2i:
	var predators: int = 0
	var prey: int = 0
	for node in get_tree().get_nodes_in_group(Cell.PREDATOR_GROUP):
		if not node.is_queued_for_deletion():
			predators += 1
	for node in get_tree().get_nodes_in_group(Cell.FLOATER_GROUP):
		if not node.is_queued_for_deletion() and not node.is_in_group(Cell.PREDATOR_GROUP):
			prey += 1
	return Vector2i(predators, prey)

## How fast this colony is breeding, as a multiple of its own spawn_interval.
## Asked of the cells rather than of the colony resource because the answer can
## depend on what they are living through, which the resource knows nothing
## about. One member speaks for all of them -- the drip feed is a single clock
## for the species, not something each cell keeps its own copy of -- and a
## colony with nobody left simply breeds at its plain pace, which is the pace it
## is being re-seeded at anyway.
func _breeding_rate(index: int) -> float:
	# _living() prunes the eaten as it counts, so the survivor it leaves at the
	# front is a cell that is genuinely still there to be asked.
	if _living(index) == 0:
		return 1.0
	return _alive[index][0].breeding_rate()

## Whether this colony already has as many alive as it is allowed. A
## max_population of 0 means no ceiling, which is every colony bar the ones that
## have specifically asked for one.
func _at_cap(index: int) -> bool:
	var cap: int = colonies[index].max_population
	return cap > 0 and _living(index) >= cap

## Living members of this colony, dropping any eaten since the last check.
## queue_free() only takes effect at the end of the frame, so a cell claimed
## this frame still has to count as gone or it blocks its own replacement.
func _living(index: int) -> int:
	var living: Array = _alive[index]
	for i in range(living.size() - 1, -1, -1):
		# Untyped: a freed instance cannot be assigned to a Cell-typed variable.
		var cell = living[i]
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			living.remove_at(i)
	return living.size()

## Places one cell of this colony. `at` is where a summon wants it dropped; left
## at the sentinel (the drip-feed case) the colony picks its own spot. Either way
## the cell is set up identically from here down.
func _spawn_cell(index: int, at: Vector2 = Vector2.INF) -> void:
	var colony: CellColony = colonies[index]
	if colony.scene == null:
		return

	var cell: Cell = colony.scene.instantiate()
	cell.position = _spawn_position(colony) if at == Vector2.INF else _clamped_to_dish(at)
	# Spawning somewhere is not the same as belonging there: by default a cell is
	# free to cross the whole dish, and only stays put if the colony asks for it.
	if colony.roam_radius <= 0.0 and dish != null:
		var leash: Vector2 = dish.leash_radii()
		cell.roam_center = dish.global_position
		cell.roam_radius = leash.x
		cell.roam_scale = Vector2(1.0, leash.y / maxf(leash.x, 0.001))
	else:
		# A colony that asked for its own patch gets a round one; only the dish
		# itself is an oval.
		cell.roam_center = colony.spawn_center
		cell.roam_radius = _leash_for(colony)
		cell.roam_scale = Vector2.ONE

	if not colony.textures.is_empty():
		# @onready has not run yet, so reach for the node directly.
		var sprite: Sprite2D = cell.get_node("Sprite2D")
		sprite.texture = colony.textures.pick_random()

	add_child(cell)
	_alive[index].append(cell)

## Where one cell of this colony starts. Anywhere in the dish unless the colony
## specifically asks to be dropped in a patch, and clamped either way so nothing
## can be placed out through the glass.
func _spawn_position(colony: CellColony) -> Vector2:
	if colony.spawn_at_rim and dish != null:
		return dish.global_position + _random_on_rim(dish.leash_radii(), colony.spawn_rim_depth)
	if colony.spawn_anywhere and dish != null:
		return dish.global_position + _random_in_oval(dish.leash_radii())
	return _clamped_to_dish(
		colony.spawn_center + _random_in_oval(Vector2.ONE * colony.spawn_radius))

## A point in the band just inside the leash: an even bearing, at a random depth
## through the outer `depth` of the oval. Even by bearing rather than by area,
## which is the opposite of _random_in_oval and deliberately so -- a rim colony
## wants to arrive spread right around the glass, not bunched into the stretches
## where the oval happens to be widest.
func _random_on_rim(of_radii: Vector2, depth: float) -> Vector2:
	var inset: float = 1.0 - randf() * clampf(depth, 0.0, 1.0)
	return Vector2.RIGHT.rotated(randf() * TAU) * of_radii * inset

## Uniformly distributed point inside an oval of these radii. The square root is
## what makes it even by area -- sampling the radius directly bunches cells up
## around the centre, and a plain x/y box (which this replaces) scatters them
## into corners the dish does not have. Scaling an even disc by the radii keeps
## it even once it is stretched.
func _random_in_oval(of_radii: Vector2) -> Vector2:
	return Vector2.RIGHT.rotated(randf() * TAU) * sqrt(randf()) * of_radii

## A colony that wants its own patch gets one, shrunk so the patch still fits
## inside the glass from wherever it happens to be centred.
func _leash_for(colony: CellColony) -> float:
	if dish == null:
		return colony.roam_radius

	# How far out the colony sits as a fraction of the oval, then how much of the
	# short axis is left beyond that. Direction-aware, because a patch out along
	# the wide axis has far more room than the same offset up the narrow one --
	# and still conservative, since a round patch has to fit whichever way the
	# oval is tightest.
	var leash: Vector2 = dish.leash_radii()
	var out: float = ((colony.spawn_center - dish.global_position) / leash).length()
	var room: float = (1.0 - out) * minf(leash.x, leash.y)
	if room <= 0.0:
		push_warning("Colony centred at %s sits outside the dish." % colony.spawn_center)
		return 0.0
	return minf(colony.roam_radius, room)

func _fit_camera_to_dish() -> void:
	if dish == null or camera == null:
		return
	# Limits smaller than the viewport lock the camera dead centre, so a dish
	# that fits on screen simply stops panning.
	var centre: Vector2 = dish.global_position
	var extent: Vector2 = dish.radii()
	camera.limit_left = int(centre.x - extent.x)
	camera.limit_right = int(centre.x + extent.x)
	camera.limit_top = int(centre.y - extent.y)
	camera.limit_bottom = int(centre.y + extent.y)
