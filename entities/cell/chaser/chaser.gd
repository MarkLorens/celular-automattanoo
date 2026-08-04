class_name Chaser
extends Cell

## Predator. Drifts slower than everything else until a floater wanders into its
## sensor, then commits to a short burst of pursuit and gives up whether or not
## it ever closed the distance.
##
## The hunt is a burst rather than a pursuit to the death on purpose: lock on,
## chase for hunt_duration, rest for hunt_cooldown, back to drifting. Boosted,
## the chaser is only fractionally quicker than its prey, so most hunts are
## supposed to end in nothing.
##
## Detection is two stage on purpose: the sensor's collision mask decides what
## is physically detectable, then FLOATER_GROUP decides what counts as food.
## A new prey species needs both -- its physics layer added to the sensor mask,
## and the group joined in its own _ready().

@export_group("Hunting")
## Speed and steering are scaled by this while locked on.
@export var chase_multiplier: float = 1.2
@export var pursuit_weight: float = 2.0
## How long one hunt runs, from lock-on to giving up.
@export var hunt_duration: float = 2.0
## Breather once a hunt ends, during which floaters in the sensor are ignored.
## Without it the chaser re-locks the frame it gives up and hunts forever.
@export var hunt_cooldown: float = 1.5
## Wander is damped to this fraction while locked on, so a burst reads as a
## committed lunge rather than a slightly faster meander.
@export var hunt_wander_scale: float = 0.15
## Centre-to-centre distance at which prey is caught and removed. The colliders
## are 86 and 79 across, so anything under ~165 means the two are already
## overlapping -- a chaser passes through prey rather than bumping into it, so
## there is no contact for physics to report and this is the only test there is.
@export var catch_radius: float = 100.0

@export_group("Temperature")
## Speed multiplier once the dish is colder than chill_celsius. A flat step, not
## a ramp: the chaser gets no faster still as the dish keeps cooling, so there
## is a single "cold chaser" speed to balance against rather than a sliding one.
@export var chill_multiplier: float = 2.0
## At this temperature and above the chaser runs at its normal speed. Below it,
## chill_multiplier applies.
@export var chill_celsius: float = 15.0

@onready var sensor: Area2D = $Area2D

var prey: Cell = null

# max_speed/max_force/wander_weight get scaled in place while hunting, so the
# boost reaches separation and containment too rather than only the pursuit
# force. These hold the unboosted values to scale from.
var _cruise_speed: float = 0.0
var _cruise_force: float = 0.0
var _cruise_wander: float = 0.0

var _hunt_remaining: float = 0.0
var _cooldown_remaining: float = 0.0

func _ready() -> void:
	super()  # GDScript does not chain _ready(); without this Cell's never runs.
	add_to_group("chaser")
	add_to_group(PREDATOR_GROUP)
	_cruise_speed = max_speed
	_cruise_force = max_force
	_cruise_wander = wander_weight

func is_hunting() -> bool:
	return prey != null

## Whether the dish is cold enough to have sped this chaser up. Strictly below,
## so the stated threshold itself is still normal speed.
func is_chilled() -> bool:
	return dish_celsius < chill_celsius

func _steering(delta: float) -> Vector2:
	_catch_touching()
	_update_hunt(delta)

	# The cold multiplies the hunt rather than replacing it, so a chilled chaser
	# mid-burst is very quick indeed. That compounding is deliberate.
	var boost: float = chase_multiplier if is_hunting() else 1.0
	boost *= chill_multiplier if is_chilled() else 1.0
	max_speed = _cruise_speed * boost
	# Turning force rides along with speed, as it does for the hunt boost. A
	# chaser given twice the speed and the same force would swing wide on every
	# corner instead of simply being faster.
	max_force = _cruise_force * boost
	wander_weight = _cruise_wander * (hunt_wander_scale if is_hunting() else 1.0)

	if not is_hunting():
		return Vector2.ZERO  # Cell's wander does the aimless drifting.

	# Aim where the prey is going rather than where it is, so the chaser cuts
	# the corner instead of trailing along behind it.
	var offset: Vector2 = prey.global_position - global_position
	var lead: float = offset.length() / maxf(max_speed, 1.0)
	return _steer_toward(offset + prey.velocity * lead) * pursuit_weight

## Drift -> lock on -> burst -> rest -> drift. Exactly one of the three phases
## is live on any given frame.
func _update_hunt(delta: float) -> void:
	if prey != null and not is_edible(prey):
		_end_hunt()  # Freed, or already claimed by another chaser, mid-chase.

	if is_hunting():
		# The catch itself is not here any more -- _catch_touching() does it, for
		# anything the chaser is touching rather than only what it is chasing.
		# Deliberately not re-reading the sensor here: the chaser commits for
		# the whole burst, so prey skimming the sensor edge cannot flicker the
		# hunt on and off, and prey that escapes still gets chased to the end.
		_hunt_remaining -= delta
		if _hunt_remaining <= 0.0:
			_end_hunt()
		return

	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta
		return

	var target: Cell = _nearest_floater()
	if target != null:
		prey = target
		_hunt_remaining = hunt_duration

func _end_hunt() -> void:
	print("stopping hunt...")
	prey = null
	_hunt_remaining = 0.0
	_cooldown_remaining = hunt_cooldown

## Anything that ends up inside the chaser is eaten, hunting or not. The lunge
## is how the chaser tries to make contact happen -- it was never the only way
## contact happens, and one drifting straight through a floater while it rests
## should not come out the other side politely.
##
## try_eat() is what resolves it, so a defended ringer kills the chaser here
## exactly as it would at the end of a hunt.
func _catch_touching() -> void:
	for body in sensor.get_overlapping_bodies():
		var candidate := body as Cell
		if not is_edible(candidate):
			continue
		if global_position.distance_to(candidate.global_position) > catch_radius:
			continue
		var was_target: bool = candidate == prey
		if not try_eat(candidate):
			return  # That one was defended, and it just killed us.
		# Catching what it was actually after costs the usual breather. A meal
		# that simply wandered into it does not call the hunt off.
		if was_target:
			_end_hunt()
		return  # One mouthful per frame.

## A nutrient throws the chaser straight at whatever is nearest. It arrives on
## top of it, which the very next contact check turns into a kill -- or into the
## chaser's own death, when what it landed on is an armed ringer. The snap does
## not look before it leaps.
##
## Nearest anywhere rather than nearest in the sensor: a snap is not the chaser
## noticing something, it is the nutrient putting it there, and food that found
## nothing in sensor range would just look like it did nothing at all.
func on_nutrient_eaten() -> bool:
	var target: Cell = _nearest_floater_anywhere()
	if target == null:
		return true  # Nothing left alive to snap to; the food is eaten anyway.
	global_position = target.global_position
	prey = target
	_hunt_remaining = hunt_duration
	_cooldown_remaining = 0.0
	return true

## Nearest edible cell in the whole dish, sensor be damned. See on_nutrient_eaten().
func _nearest_floater_anywhere() -> Cell:
	var nearest: Cell = null
	var nearest_distance: float = INF
	for node in get_tree().get_nodes_in_group(FLOATER_GROUP):
		var candidate := node as Cell
		if not is_edible(candidate):
			continue
		var distance: float = global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest

## Nearest cell in the sensor that counts as food, or null if there is none.
## Picking the nearest means a chaser in the middle of a shoal lunges at
## whoever is closest at lock-on, then sticks with them for the whole burst.
func _nearest_floater() -> Cell:
	var nearest: Cell = null
	var nearest_distance: float = INF
	for body in sensor.get_overlapping_bodies():
		var candidate := body as Cell
		if candidate == null or not is_edible(candidate):
			continue
		var distance: float = global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest
