class_name Flocker
extends Cell

## Tight boid formation: line up with the neighbours and pull in toward their
## centre. Separation, wander and containment come from Cell.
##
## The one species that reacts to predators, and it does so as a shoal rather
## than as individuals. A flocker that can see a predator panics directly; that
## panic then spreads colony-mate to colony-mate, so cells that never saw
## anything still break formation and burst outward. Ringers hold their shell.
##
## Panic does three things at once, all scaled by how frightened the cell is:
## it dissolves formation, it throws the cell out from the flock centre, and
## (for cells that can actually see the threat) it steers away from the
## predator itself. None of it touches speed -- a flocker outruns nothing, it
## only turns sooner.

@export_group("Flocking")
@export var alignment_weight: float = 1.0
@export var cohesion_weight: float = 0.9

@export_group("Fleeing")
## Weight of the escape force, applied only by cells that can see the predator.
@export var flee_weight: float = 3.0
## Strength of the escape at the very rim of the sensor, ramping to full as the
## predator closes. Stops a flocker from jerking sideways the moment a chaser
## clips the edge of its bubble. Panic is what covers the outer band instead.
@export var flee_edge_scale: float = 0.15

@export_group("Panic")
## Fraction of a neighbour's alarm that carries across. Below 1 so fear thins
## with every hop rather than pinning the whole colony at full panic.
@export var alarm_contagion: float = 0.85
## Alarm per second climbing toward the frightening level. Finite so the panic
## visibly sweeps out through the flock instead of snapping on everywhere.
@export var alarm_rise: float = 4.0
## Alarm per second bleeding off once the threat has passed. Slow, so the flock
## stays scattered for a moment and re-forms in its own time.
@export var alarm_decay: float = 0.6
## Outward burst from the flock centre at full alarm -- the shoal blowing apart.
## A cell that never saw the predator has no direction to run in, so this is
## what it runs on.
@export var scatter_weight: float = 2.0
## Formation left at full alarm. Low, or cohesion just drags frightened cells
## back into the predator's path -- which is where the flock centre tends to be.
@export var panic_formation_scale: float = 0.1

@export_group("Reproduction")
## How far from the parent a new flocker appears. Small, so it reads as budding
## off rather than materialising elsewhere; separation does the pushing apart.
@export var offspring_offset: float = 60.0

@onready var threat_sensor: Area2D = $Area2D

# Refilled by _sense_threats() each frame, the same way Cell fills the
# neighbour fields: how frightening this cell's own view is, and where to run.
var _direct_alarm: float = 0.0
var _escape: Vector2 = Vector2.ZERO

# Sensor reach, read off the collision shape so the falloff always matches the
# bubble drawn in the editor instead of a second value that can drift from it.
var _threat_radius: float = 0.0

func _ready() -> void:
	super()  # GDScript does not chain _ready(); without this Cell's never runs.
	add_to_group("flocker")
	add_to_group(FLOATER_GROUP)
	_threat_radius = _sensor_radius()

## Eating is how flockers multiply -- the one species that turns food into more
## of itself. The newborn is a duplicate rather than a fresh scene instance so it
## inherits the parent's leash, tuning and sprite instead of reverting to the
## scene defaults, which would leash it to the wrong patch entirely.
func on_nutrient_eaten() -> bool:
	var child := duplicate() as Flocker
	if child != null:
		child.position = position + Vector2.RIGHT.rotated(randf() * TAU) * offspring_offset
		# The tree cannot be touched while the physics server is flushing
		# queries, and that is exactly when a nutrient reports being eaten.
		get_parent().add_child.call_deferred(child)
	return true

func _steering(delta: float) -> Vector2:
	_sense_threats()
	_update_alarm(delta)

	# Both terms apply to a lone flocker too: losing the flock is the usual
	# result of being chased, not a reason to calm down.
	var steering: Vector2 = _escape * flee_weight \
		+ _scatter_steering() * scatter_weight * alarm

	if neighbour_count == 0:
		return steering

	# Formation dissolves as panic rises, so a spooked flock breaks up instead
	# of hauling its own frightened members back toward the thing chasing them.
	var formation: float = lerpf(1.0, panic_formation_scale, alarm)
	return steering \
		+ _steer_toward(colony_heading) * alignment_weight * formation \
		+ _steer_toward(colony_centre - global_position) * cohesion_weight * formation

## Panic is the louder of what this cell can see for itself and what its
## neighbours are already feeling. Climbs quickly, bleeds off slowly, and
## settles at whatever the flock around it is sustaining.
func _update_alarm(delta: float) -> void:
	var target: float = maxf(_direct_alarm, neighbour_alarm * alarm_contagion)
	if target > alarm:
		alarm = minf(alarm + alarm_rise * delta, target)
	else:
		alarm = maxf(alarm - alarm_decay * delta, target)

## Everything the threat sensor has to say this frame: how frightening it is,
## and which way to run. Away from every predator in range at once, so a flocker
## caught between two of them splits the difference instead of picking one and
## bolting into the other.
func _sense_threats() -> void:
	_direct_alarm = 0.0
	_escape = Vector2.ZERO

	var heading: Vector2 = Vector2.ZERO
	for body in threat_sensor.get_overlapping_bodies():
		var threat := body as Cell
		if threat == null or not threat.is_in_group(PREDATOR_GROUP):
			continue
		var offset: Vector2 = global_position - threat.global_position
		var distance: float = offset.length()
		if is_zero_approx(distance):
			continue
		var closeness: float = _closeness(distance)
		heading += offset / distance * closeness
		_direct_alarm = maxf(_direct_alarm, closeness)

	if heading.is_zero_approx():
		return
	# _steer_toward normalises, so the falloff has to be reapplied outside it or
	# a predator at the rim would shove just as hard as one about to land.
	_escape = _steer_toward(heading) * _direct_alarm

## Straight out from the flock centre. This is the burst that makes a shoal blow
## apart when something hits its edge, and the only thing a cell with no sight
## of the predator has to go on.
func _scatter_steering() -> Vector2:
	if neighbour_count == 0 or is_zero_approx(alarm):
		return Vector2.ZERO
	return _steer_toward(global_position - colony_centre)

## 1.0 with a predator on top of us, easing to flee_edge_scale at the sensor rim.
func _closeness(distance: float) -> float:
	if _threat_radius <= 0.0:
		return 1.0
	return lerpf(1.0, flee_edge_scale, clampf(distance / _threat_radius, 0.0, 1.0))

## Reach of the threat sensor, or 0 if it is not a plain circle -- in which case
## the falloff is skipped and every detected predator counts as close.
func _sensor_radius() -> float:
	var shape_node: CollisionShape2D = threat_sensor.get_node_or_null("CollisionShape2D")
	if shape_node == null:
		return 0.0
	var circle := shape_node.shape as CircleShape2D
	if circle == null:
		return 0.0
	return circle.radius
