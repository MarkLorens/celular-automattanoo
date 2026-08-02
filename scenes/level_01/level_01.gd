extends Node

@export var flock_scene: PackedScene
@export var flock_count: int = 20
@export var spawn_radius: float = 1000.0
@export var flock_textures: Array[Texture2D] = []

func _ready() -> void:
	for i in flock_count:
		spawn_flock_member()

func spawn_flock_member():
	var member := flock_scene.instantiate()
	member.position = Vector2(
		randf_range(-spawn_radius, spawn_radius),
		randf_range(-spawn_radius, spawn_radius)
	)
	
	if flock_textures.size() > 0:
		var sprite: Sprite2D = member.get_node("Sprite2D")
		sprite.texture = flock_textures.pick_random()
		
	add_child(member)
