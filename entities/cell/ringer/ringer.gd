class_name Ringer
extends Cell

## Settles onto a shell around the colony centre rather than filling it in,
## and orbits so the ring keeps turning instead of parking.
##
## Cohesion is replaced by a signed radial force: pull inward when outside the
## shell, push outward when inside. Separation (from Cell) is what spaces the
## cells out along it -- which is why the radius and the cell count are tied
## together, see _fit_radius().

@export_group("Ring")
## Radius of the shell -- or the cap on it while auto_fit_radius is on.
@export var ring_radius: float = 900.0
## Size the ring from the live population instead, so it stays a clean circle
## as cells are added or lost. Stops growing at ring_radius, past which the
## shell just packs denser rather than expanding forever.
@export var auto_fit_radius: bool = true
@export var radial_weight: float = 1.6
## Tangential push. 0 leaves a static shell of parked cells; higher spins faster.
@export var orbit_weight: float = 1.0

@export_group("Defence")
## How long a nutrient's protection lasts. While it holds, a predator that
## reaches this ringer dies on it instead of eating.
@export var defence_duration: float = 10.0

@export_group("Temperature")
## Speed at the cold end of the gauge, and at the hot end. In between sits
## neutral_celsius, where the ringer runs at whatever max_speed its scene sets.
## The curve hinges there rather than running straight from cold to hot, so the
## scene's value stays the honest "normal" instead of being quietly overridden.
@export var cold_speed: float = 60.0
@export var hot_speed: float = 200.0
@export var cold_celsius: float = 0.0
@export var neutral_celsius: float = 50.0
@export var hot_celsius: float = 100.0

var _defence_remaining: float = 0.0

# max_speed and min_speed are rewritten every frame from the dish temperature,
# so these hold the scene's own values for the curve to hinge on.
var _base_max: float = 0.0
var _base_min: float = 0.0

func _ready() -> void:
	super()  # GDScript does not chain _ready(); without this Cell's never runs.
	add_to_group("ringer")
	add_to_group(FLOATER_GROUP)
	_base_max = max_speed
	_base_min = min_speed

func _physics_process(delta: float) -> void:
	_defence_remaining = maxf(_defence_remaining - delta, 0.0)
	_apply_temperature()
	super(delta)  # Only the most derived _physics_process is called.

## Warm medium thins out and the ringer drifts faster through it; cold thickens
## and it slows. Two straight runs meeting at neutral_celsius, because the scene
## speed is the middle of the range rather than the average of its ends.
func _apply_temperature() -> void:
	var target: float = _blend(dish_celsius, cold_celsius, neutral_celsius,
		cold_speed, _base_max)
	if dish_celsius > neutral_celsius:
		target = _blend(dish_celsius, neutral_celsius, hot_celsius,
			_base_max, hot_speed)
	max_speed = target
	# The floor rides along with the ceiling. Left alone it could end up above
	# max_speed in the cold, and a ringer's slowest drift ought to answer to the
	# temperature too.
	min_speed = _base_min * target / maxf(_base_max, 0.001)

## Straight-line blend that survives a zero-width span instead of dividing by
## zero, and never reads past either end.
static func _blend(value: float, from: float, to: float,
		low: float, high: float) -> float:
	if is_equal_approx(from, to):
		return high
	return low + (high - low) * clampf((value - from) / (to - from), 0.0, 1.0)

func is_defended() -> bool:
	return _defence_remaining > 0.0

## Seconds of protection left, for anything that wants to show it.
func defence_remaining() -> float:
	return _defence_remaining

## A nutrient turns this ringer poisonous for a while rather than feeding it.
## Already-protected ringers turn food down instead of topping the timer up, so
## a shoal of them cannot sit on the food supply and stay permanently armed.
func on_nutrient_eaten() -> bool:
	if is_defended():
		return false
	_defence_remaining = defence_duration
	Audio.play_sfx(eat_sound)
	return true

func _steering(_delta: float) -> Vector2:
	if neighbour_count == 0:
		return Vector2.ZERO

	var to_centre: Vector2 = colony_centre - global_position
	var distance: float = to_centre.length()
	if is_zero_approx(distance):
		return Vector2.ZERO

	var inward: Vector2 = to_centre / distance
	var target: float = _fit_radius() if auto_fit_radius else ring_radius
	var error: float = distance - target

	# Signed radial correction, easing off as we near the shell so cells settle
	# onto it instead of oscillating back and forth through it.
	var urgency: float = minf(absf(error) / target, 1.0)
	var steering: Vector2 = _steer_toward(inward * signf(error)) * radial_weight * urgency
	steering += _steer_toward(inward.orthogonal()) * orbit_weight
	return steering

## Radius at which n cells sit exactly separation_radius apart around the ring.
## Too small and separation buckles the shell into a blob; too large and the
## cells string out into disconnected arcs.
func _fit_radius() -> float:
	var n: int = neighbour_count + 1
	if n < 3:
		return ring_radius
	return minf(separation_radius / (2.0 * sin(PI / float(n))), ring_radius)
