class_name Flocker
extends Cell

## Tight boid formation: line up with the neighbours and pull in toward their
## centre. Separation, wander and containment come from Cell.

@export_group("Flocking")
@export var alignment_weight: float = 1.0
@export var cohesion_weight: float = 0.9

func _steering(_delta: float) -> Vector2:
	if neighbour_count == 0:
		return Vector2.ZERO
	return _steer_toward(colony_heading) * alignment_weight \
		+ _steer_toward(colony_centre - global_position) * cohesion_weight
