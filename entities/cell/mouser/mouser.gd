class_name Mouser
extends Cell

## Ambient hazard. Drifts toward the cursor and consumes whatever it happens to
## be overlapping on the way. It does not sense prey, choose between targets or
## give chase -- anything that ends up inside it is simply gone, and anything
## that stays out of the way is never noticed.
##
## Movement is entirely its own: _physics_process is replaced rather than
## extended, so none of Cell's neighbour gathering, separation or containment
## applies. It counts as a predator only so that nothing eats it and it eats
## nothing that hunts.

@export var arrive_radius: float = 60.0
@export var smoothing: float = 2.0
@export var wander_strength: float = 40.0
@export var change_interval: float = 2.0
## Centre-to-centre distance at which an overlapped cell is consumed. The mouser
## is 59 across and prey 79, so this only fires once prey is genuinely inside it.
@export var consume_radius: float = 80.0

@export_group("Feeding")
## Every nutrient makes the mouser this much bigger -- sprite, collider and the
## reach it consumes at, so it grows into a wider hazard rather than just a
## larger picture of one. Compounds with each meal.
@export var growth_per_nutrient: float = 1.1
## Speed multiplier while a nutrient's burst lasts. Only the top speed moves;
## the steering underneath is untouched, so it still just drifts at the cursor.
@export var speed_burst: float = 2.0
## How long that burst runs. Eating again refreshes it rather than stacking it.
@export var burst_duration: float = 10.0

var wander_offset: Vector2 = Vector2.ZERO
var time_until_change: float = 0.0

# max_speed is rewritten in place while bursting, so this holds the value to
# scale from -- the same trick the chaser uses for its hunt boost.
var _cruise_speed: float = 0.0
var _burst_remaining: float = 0.0


func _ready() -> void:
	# Deliberately no super(): Cell's _ready only seeds the wander angle, spin
	# and starting velocity that this species replaces wholesale. The group tags
	# are the one part that still has to happen, and they are what keep the
	# mouser and the chaser from ever treating each other as a meal.
	add_to_group("mouser")
	add_to_group(PREDATOR_GROUP)
	_cruise_speed = max_speed
	_pick_new_wander()

func _physics_process(delta: float) -> void:
	time_until_change -= delta
	if time_until_change <= 0.0:
		_pick_new_wander()

	_burst_remaining = maxf(_burst_remaining - delta, 0.0)
	max_speed = _cruise_speed * (speed_burst if is_bursting() else 1.0)

	# Steer toward the mouse, plus a per-member wander offset so they don't all stack.
	# Clamping the target rather than the mouser is what keeps this smooth: with the
	# cursor outside the glass it tracks the nearest point on the rim and slides
	# along it, instead of pressing outward against a wall.
	var mouse_pos: Vector2 = get_global_mouse_position()
	var to_target: Vector2 = _clamped_to_roam(mouse_pos + wander_offset) - global_position
	var distance: float = to_target.length()

	var desired_speed: float = max_speed
	# Ease off speed as they get close, so they mill around instead of piling on the cursor
	if distance < arrive_radius:
		desired_speed = remap(distance, 0.0, arrive_radius, min_speed, max_speed)

	var target_velocity: Vector2 = to_target.normalized() * desired_speed
	velocity = velocity.lerp(target_velocity, smoothing * delta)
	move_and_slide()
	# Backstop. Clamping the target keeps it honest almost all the time, but a
	# fast flick of the cursor can still carry the mouser a little past the rim
	# on momentum, and it has no collider to stop it -- it passes through
	# everything, the glass included.
	global_position = _clamped_to_roam(global_position)
	_consume_overlapped()

	# Rotation stays independent — random tumble, unaffected by heading
	current_angular_speed = lerp(current_angular_speed, target_angular_speed, smoothing * delta)
	sprite.rotation += current_angular_speed * delta

## Nearest point inside the roaming circle the level handed us on spawn -- the
## same leash every other species is held to, so the mouser cannot chase the
## cursor out through the glass. A roam_radius of 0 means no leash, matching how
## Cell._containment_steering() reads it, and passes the point back untouched.
func _clamped_to_roam(point: Vector2) -> Vector2:
	if roam_radius <= 0.0:
		return point
	var offset: Vector2 = point - roam_center
	if offset.length() <= roam_radius:
		return point
	return roam_center + offset.normalized() * roam_radius

## Eat everything currently inside us. There is no sensor and no physics contact
## to work from -- the mouser passes clean through the dish -- so this walks the
## live floaters directly. is_edible() is the same rule the chaser eats by, so a
## cell already claimed this frame is left alone and predators are never food.
func _consume_overlapped() -> void:
	var reach: float = consume_radius * consume_radius
	for node in get_tree().get_nodes_in_group(FLOATER_GROUP):
		var other := node as Cell
		if not is_edible(other):
			continue
		if global_position.distance_squared_to(other.global_position) > reach:
			continue
		if not try_eat(other):
			return  # Bounced off a defended one. Nothing more is eaten this frame.

func is_bursting() -> bool:
	return _burst_remaining > 0.0

## Seconds of speed burst left, for anything that wants to show it.
func burst_remaining() -> float:
	return _burst_remaining

## A nutrient makes the mouser bigger and briefly faster. Nothing about how it
## moves or what it eats changes -- it is the same drift and the same rule,
## carried out at a larger radius and a higher top speed.
func on_nutrient_eaten() -> bool:
	scale *= growth_per_nutrient
	consume_radius *= growth_per_nutrient
	_burst_remaining = burst_duration
	return true

## The mouser is too dumb to be poisoned. It bumps off a defended ringer and
## carries on, and the ringer is knocked back just as hard -- the one predator
## that survives the encounter.
func _on_defended_prey(prey: Cell) -> void:
	var offset: Vector2 = global_position - prey.global_position
	var away: Vector2 = offset.normalized()
	if away.is_zero_approx():
		away = Vector2.RIGHT.rotated(randf() * TAU)

	# Separate them as well as turning them around. Velocity alone is not enough
	# when the mouser has no collider to stop it: it would stay inside the ringer
	# and re-trigger the bounce every frame, buzzing instead of rebounding.
	var overlap: float = consume_radius - offset.length() + 4.0
	if overlap > 0.0:
		global_position = _clamped_to_roam(global_position + away * overlap * 0.5)
		prey.global_position -= away * overlap * 0.5

	velocity = away * maxf(velocity.length(), min_speed)
	prey.velocity = -away * maxf(prey.velocity.length(), prey.min_speed)

func _pick_new_wander() -> void:
	target_angular_speed = randf_range(-max_angular_speed, max_angular_speed)
	wander_offset = Vector2(
		randf_range(-wander_strength, wander_strength),
		randf_range(-wander_strength, wander_strength)
	)
	time_until_change = change_interval + randf_range(-0.5, 0.5)
