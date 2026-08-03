class_name Cell
extends CharacterBody2D

## Shared machinery for every cell species: neighbour gathering, force
## integration, the roaming leash and the sprite spin.
##
## Species subclasses supply _steering() and nothing else. Separation, wander
## and containment are handled here because all three species need them -- a
## subclass only has to express what actually makes it different.

@export_group("Movement")
@export var min_speed: float = 60.0
@export var max_speed: float = 160.0
## Steering acceleration cap in px/s². Lower values mean wider, lazier turns.
@export var max_force: float = 260.0

@export_group("Perception")
## How far a cell looks for others of its own kind.
@export var view_radius: float = 600.0
## Anything nearer than this gets shoved away. Sits above the collider diameter
## (2 x 79px) so cells steer apart before their bodies actually bump.
@export var separation_radius: float = 260.0
@export var separation_weight: float = 1.6

@export_group("Wander")
@export var wander_weight: float = 1.0
## The wander target rides a circle projected this far ahead of the cell.
@export var wander_distance: float = 120.0
@export var wander_radius: float = 90.0
## Radians per second the target is allowed to drift around that circle.
@export var wander_jitter: float = 4.0

@export_group("Roaming Area")
## Soft leash so a colony never disappears off the map. 0 turns it off.
@export var roam_radius: float = 1200.0
@export var roam_center: Vector2 = Vector2.ZERO
@export var containment_weight: float = 2.5

@export_group("Funny Rotate")
@export var max_angular_speed: float = 1.5
@export var spin_change_interval: float = 2.0
@export var spin_smoothing: float = 2.0

@onready var sprite: Sprite2D = $Sprite2D

## Anything that merely drifts, i.e. everything a predator treats as food.
## Prey species opt in from their own _ready(); predators do not.
const FLOATER_GROUP := &"floater"

## Anything that hunts. Predator species opt in from their own _ready(). Prey
## that bothers to look for danger keys off this rather than a species name, so
## a second predator spooks everything the first one does.
const PREDATOR_GROUP := &"predator"

## Live cells bucketed by species, keyed on the species script itself. Species
## never perceive each other, so a cell only ever walks its own bucket -- and
## the script being the key means a species cannot be mis-tagged.
static var colonies: Dictionary = {}

## How spooked this cell is, 0 to 1. Cell never acts on it and never sets it --
## it lives here so the one neighbour pass can carry fear between colony-mates,
## and so a species that does not care about predators just leaves it at zero.
var alarm: float = 0.0

# Refilled by _gather_neighbours() each frame, read by _steering().
var neighbour_count: int = 0
var crowding: int = 0
var colony_centre: Vector2 = Vector2.ZERO
var colony_heading: Vector2 = Vector2.ZERO
var separation_push: Vector2 = Vector2.ZERO
## Loudest alarm among the colony-mates in view. This is the whole of the panic
## channel: a species that reads it inherits its neighbours' fear.
var neighbour_alarm: float = 0.0

var _colony: Array = []
var wander_angle: float = 0.0
var target_angular_speed: float = 0.0
var current_angular_speed: float = 0.0
var time_until_spin_change: float = 0.0

func _enter_tree() -> void:
	var species: Script = get_script()
	if not colonies.has(species):
		colonies[species] = []
	_colony = colonies[species]
	_colony.append(self)

# Leaving the *scene tree* only, i.e. freed or reparented. A cell that drifts
# away from its colony is still in here, still wandering on its own.
func _exit_tree() -> void:
	_colony.erase(self)

func _ready() -> void:
	wander_angle = randf() * TAU
	velocity = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(min_speed, max_speed)
	_pick_new_spin()

func _physics_process(delta: float) -> void:
	_gather_neighbours()

	var steering: Vector2 = _steering(delta)
	steering += _wander_steering(delta) * wander_weight
	if crowding > 0:
		steering += _steer_toward(separation_push) * separation_weight
	steering += _containment_steering() * containment_weight

	velocity += steering.limit_length(max_force) * delta
	velocity = _clamp_speed(velocity)
	move_and_slide()

	_spin_sprite(delta)

## The one test for "may a predator eat this", shared by every predator so the
## rule cannot drift apart between them. Predators are excluded explicitly
## rather than by merely not being floaters: two predators drifting through each
## other must never end in a meal, however either one was tagged.
##
## is_queued_for_deletion() is the load-bearing part. queue_free() does not take
## the node away until the end of the frame, so is_instance_valid() still
## answers true for prey another predator already claimed this same frame.
## The argument is deliberately untyped. A predator can still be holding a
## reference to prey a *different* predator ate on an earlier frame, and passing
## an already-freed object to a `Cell`-typed parameter raises a type error
## instead of quietly answering false -- which is the one answer this has to be
## able to give.
static func is_edible(cell) -> bool:
	if not is_instance_valid(cell):
		return false
	var candidate := cell as Cell
	return candidate != null \
		and not candidate.is_queued_for_deletion() \
		and candidate.is_in_group(FLOATER_GROUP) \
		and not candidate.is_in_group(PREDATOR_GROUP)

## Called by a nutrient as it is eaten. A species that makes something of a meal
## overrides this; for everyone else food is just food and nothing comes of it.
func on_nutrient_eaten() -> void:
	pass

## What makes this species this species. Overridden by every subclass.
func _steering(_delta: float) -> Vector2:
	return Vector2.ZERO

## One pass over the colony, feeding whatever the species happens to need.
func _gather_neighbours() -> void:
	neighbour_count = 0
	crowding = 0
	colony_centre = Vector2.ZERO
	colony_heading = Vector2.ZERO
	separation_push = Vector2.ZERO
	neighbour_alarm = 0.0

	var view_sq: float = view_radius * view_radius
	var separation_sq: float = separation_radius * separation_radius

	for other in _colony:
		if other == self:
			continue
		var offset: Vector2 = other.global_position - global_position
		var distance_sq: float = offset.length_squared()
		if distance_sq > view_sq or is_zero_approx(distance_sq):
			continue

		neighbour_count += 1
		colony_heading += other.velocity
		colony_centre += other.global_position
		# Fear travels one cell per frame. Whether a neighbour has already
		# updated this frame depends on tree order, which at 60Hz is far below
		# what the rise rate on the reading end makes visible.
		neighbour_alarm = maxf(neighbour_alarm, other.alarm)

		if distance_sq < separation_sq:
			# Inverse distance falloff: the closer the neighbour, the harder the shove.
			separation_push -= offset / distance_sq
			crowding += 1

	if neighbour_count > 0:
		colony_centre /= float(neighbour_count)
		colony_heading /= float(neighbour_count)

## Meandering, so a lone cell (or a colony that has settled) still goes somewhere.
func _wander_steering(delta: float) -> Vector2:
	wander_angle += randf_range(-wander_jitter, wander_jitter) * delta
	var heading: Vector2 = velocity.normalized()
	if heading.is_zero_approx():
		heading = Vector2.RIGHT.rotated(wander_angle)
	return _steer_toward(heading * wander_distance + Vector2.RIGHT.rotated(wander_angle) * wander_radius)

func _containment_steering() -> Vector2:
	if roam_radius <= 0.0:
		return Vector2.ZERO
	var to_center: Vector2 = roam_center - global_position
	if to_center.length() < roam_radius:
		return Vector2.ZERO
	return _steer_toward(to_center)

## Reynolds steering: the force that bends our current velocity toward the desired one.
func _steer_toward(direction: Vector2) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.ZERO
	return (direction.normalized() * max_speed - velocity).limit_length(max_force)

func _clamp_speed(v: Vector2) -> Vector2:
	var speed: float = v.length()
	if speed > max_speed:
		return v / speed * max_speed
	if speed < min_speed:
		if is_zero_approx(speed):
			return Vector2.RIGHT.rotated(randf() * TAU) * min_speed
		return v / speed * min_speed
	return v

func _spin_sprite(delta: float) -> void:
	time_until_spin_change -= delta
	if time_until_spin_change <= 0.0:
		_pick_new_spin()
	current_angular_speed = lerp(current_angular_speed, target_angular_speed, spin_smoothing * delta)
	sprite.rotation += current_angular_speed * delta

func _pick_new_spin() -> void:
	target_angular_speed = randf_range(-max_angular_speed, max_angular_speed)
	time_until_spin_change = spin_change_interval + randf_range(-0.5, 0.5)
