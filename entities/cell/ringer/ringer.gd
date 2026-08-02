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
