extends CharacterBody2D

@export var min_speed: float = 20.0
@export var max_speed: float = 60.0
@export var smoothing: float = 2.0
@export var max_angular_speed: float = 1.5
@export var change_interval: float = 2.0

# boid shenanigans. Not really
@export var wander_strength: float = 40.0
@export var arrive_radius: float = 60.0

@onready var sprite: Sprite2D = $Sprite2D

var target_angular_speed: float = 0.0
var current_angular_speed: float = 0.0
var wander_offset: Vector2 = Vector2.ZERO
var time_until_change: float = 0.0

func _ready() -> void:
	_pick_new_wander()

func _physics_process(delta: float) -> void:
	time_until_change -= delta
	if time_until_change <= 0.0:
		_pick_new_wander()
	
	# Find mouse
	var mouse_pos: Vector2 = get_global_mouse_position()
	var to_target: Vector2 = (mouse_pos + wander_offset) - global_position
	var distance: float = to_target.length()
	
	# Herding. Slow down as they're approaching targe
	var desired_speed: float = max_speed
	if distance < arrive_radius:
		desired_speed = remap(desired_speed, 0.0, arrive_radius, min_speed, max_speed)
	var target_velocity: Vector2 = to_target.normalized() * desired_speed
	velocity = velocity.lerp(target_velocity, smoothing * delta)
	move_and_slide()
	# Funny rotate
	current_angular_speed = lerp_angle(current_angular_speed, target_angular_speed, smoothing * delta)
	sprite.rotation += current_angular_speed * delta
	
func _pick_new_wander() -> void:
	target_angular_speed = randf_range(-max_angular_speed, max_angular_speed)
	wander_offset = Vector2(
		randf_range(-wander_strength, wander_strength),
		randf_range(-wander_strength, wander_strength)
	)
	time_until_change = change_interval + randf_range(-0.5, 0.5)
