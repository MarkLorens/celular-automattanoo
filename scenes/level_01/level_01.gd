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
	_apply_shadow_lighting()
	_fit_camera_to_dish()
	for i in colonies.size():
		var colony: CellColony = colonies[i]
		_time_until_spawn.append(colony.spawn_interval if colony != null else 0.0)
		_alive.append([])
		if colony == null:
			continue
		for n in colony.count:
			if _at_cap(i):
				break  # count overshooting max_population is the cap's problem.
			_spawn_cell(i)

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
	var offset: Vector2 = point - centre
	var limit: float = dish.leash_radius()
	if offset.length() <= limit:
		return point
	return centre + offset.normalized() * limit

func _process(delta: float) -> void:
	_nutrient_ready_in = maxf(_nutrient_ready_in - delta, 0.0)

	for i in colonies.size():
		var colony: CellColony = colonies[i]
		if colony == null or colony.spawn_interval <= 0.0:
			continue
		# A colony sitting at its cap parks its timer at full rather than burning
		# it down against a spawn that cannot happen. A kill is then followed by
		# a whole interval of absence, instead of by whatever happened to be
		# left on a clock that ran while the slot was occupied.
		if _at_cap(i):
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
		cell.roam_center = dish.global_position
		cell.roam_radius = dish.leash_radius()
	else:
		cell.roam_center = colony.spawn_center
		cell.roam_radius = _leash_for(colony)

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
		return dish.global_position + _random_in_disc(dish.leash_radius())
	return _clamped_to_dish(colony.spawn_center + _random_in_disc(colony.spawn_radius))

## Uniformly distributed point inside a circle of this radius. The square root is
## what makes it even by area -- sampling the radius directly bunches cells up
## around the centre, and a plain x/y box (which this replaces) scatters them
## into corners the round dish does not have.
func _random_in_disc(radius: float) -> Vector2:
	return Vector2.RIGHT.rotated(randf() * TAU) * sqrt(randf()) * radius

## A colony that wants its own patch gets one, shrunk so the patch still fits
## inside the glass from wherever it happens to be centred.
func _leash_for(colony: CellColony) -> float:
	if dish == null:
		return colony.roam_radius

	var offset: float = colony.spawn_center.distance_to(dish.global_position)
	var room: float = dish.leash_radius() - offset
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
	camera.limit_left = int(centre.x - dish.radius)
	camera.limit_right = int(centre.x + dish.radius)
	camera.limit_top = int(centre.y - dish.radius)
	camera.limit_bottom = int(centre.y + dish.radius)
