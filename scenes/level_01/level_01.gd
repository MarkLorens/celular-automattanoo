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
## Seconds the player waits between drops. Doubles as the real cap on how fast
## flockers can breed, since a nutrient is what buys a new one.
@export var nutrient_cooldown: float = 10.0

@export_group("Temperature")
## The gauge the player drags. Its 0..1 fill is read as a temperature between
## the two below.
@export var temperature_gauge: ArcMeter
@export var min_celsius: float = 0.0
@export var max_celsius: float = 100.0
@export var gauge_spawn_timing: float = 0

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

## Fires whenever the player moves the gauge. The dish temperature in celsius.
signal temperature_changed(celsius: float)

## Current dish temperature. Read-only from outside -- the gauge drives it.
var temperature: float = 0.0

# Counts down to 0, at which point another nutrient may be dropped.
var _nutrient_ready_in: float = 0.0

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
	temperature_gauge.hide()
	temperature_gauge.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(gauge_spawn_timing).timeout
	if not is_instance_valid(temperature_gauge):
		return  # Level torn down while the timer was running.
	temperature_gauge.show()
	temperature_gauge.process_mode = Node.PROCESS_MODE_INHERIT

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
	temperature_changed.emit(temperature)

## Whether the dish is currently too hot for this colony to drip-feed. Says
## nothing about breeding: a flocker eating a nutrient still splits at 90
## degrees, which is the whole point of the rule.
func _too_hot_for(colony: CellColony) -> bool:
	return temperature >= colony.halts_at_celsius

## _unhandled_input rather than _input, so anything the game grows later -- a
## menu, a HUD button -- gets first refusal on the key. is_action_pressed()
## ignores echoes by default, so holding the key drops one nutrient, not a
## stream of them.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("spawn_nutrient"):
		return
	if _nutrient_ready_in > 0.0:
		return  # Still cooling down. The press is refused, not queued.
	_spawn_nutrient(get_global_mouse_position())
	_nutrient_ready_in = nutrient_cooldown
	get_viewport().set_input_as_handled()

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
	_nutrient_ready_in = maxf(_nutrient_ready_in - delta, 0.0)

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
		_time_until_spawn[i] -= delta
		if _time_until_spawn[i] <= 0.0:
			_time_until_spawn[i] = colony.spawn_interval
			_spawn_cell(i)

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

func _spawn_cell(index: int) -> void:
	var colony: CellColony = colonies[index]
	if colony.scene == null:
		return

	var cell: Cell = colony.scene.instantiate()
	cell.position = _spawn_position(colony)
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
	if colony.spawn_anywhere and dish != null:
		return dish.global_position + _random_in_oval(dish.leash_radii())
	return _clamped_to_dish(
		colony.spawn_center + _random_in_oval(Vector2.ONE * colony.spawn_radius))

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
