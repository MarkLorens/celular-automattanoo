extends Node

@export var colonies: Array[CellColony] = []
## The world boundary. Every colony's leash is derived from it.
@export var dish: PetriDish
## Panning gets clamped to the dish, so you can never scroll off into the void.
@export var camera: Camera2D

# Index-aligned with colonies: each species grows on its own clock.
var _time_until_spawn: Array[float] = []

func _ready() -> void:
	_fit_camera_to_dish()
	for colony in colonies:
		_time_until_spawn.append(colony.spawn_interval if colony != null else 0.0)
		if colony == null:
			continue
		for i in colony.count:
			_spawn_cell(colony)

func _process(delta: float) -> void:
	for i in colonies.size():
		var colony: CellColony = colonies[i]
		if colony == null or colony.spawn_interval <= 0.0:
			continue
		_time_until_spawn[i] -= delta
		if _time_until_spawn[i] <= 0.0:
			_time_until_spawn[i] = colony.spawn_interval
			_spawn_cell(colony)

func _spawn_cell(colony: CellColony) -> void:
	if colony.scene == null:
		return

	var cell: Cell = colony.scene.instantiate()
	cell.position = colony.spawn_center + Vector2(
		randf_range(-colony.spawn_radius, colony.spawn_radius),
		randf_range(-colony.spawn_radius, colony.spawn_radius)
	)
	cell.roam_center = colony.spawn_center
	cell.roam_radius = _leash_for(colony)

	if not colony.textures.is_empty():
		# @onready has not run yet, so reach for the node directly.
		var sprite: Sprite2D = cell.get_node("Sprite2D")
		sprite.texture = colony.textures.pick_random()

	add_child(cell)

## A colony's leash has to fit inside the glass wherever the colony is centred,
## otherwise its cells would sit pressed against the wall. roam_radius of 0
## means "take whatever room the dish allows".
func _leash_for(colony: CellColony) -> float:
	if dish == null:
		return colony.roam_radius

	var offset: float = colony.spawn_center.distance_to(dish.global_position)
	var room: float = dish.leash_radius() - offset
	if room <= 0.0:
		push_warning("Colony centred at %s sits outside the dish." % colony.spawn_center)
		return 0.0

	if colony.roam_radius <= 0.0:
		return room
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
