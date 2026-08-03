class_name Nutrient
extends Area2D

## Food the player drops into the dish. Anything alive that touches it eats it,
## predator and prey alike -- for now with no effect beyond the nutrient going
## away. Nourishment hangs off _eat() when there is something to nourish.
##
## The nutrient does the looking rather than the cells: one Area2D that already
## knows its own shape, instead of a feeding sensor bolted onto every species.
## Its collision mask is the guest list, so a new species joins the table by
## sitting on a layer the mask covers and nothing here changes.
##
## An Area2D rather than a body on purpose: cells swim straight through it, so
## dropping food into a crowd never shoves anybody around.

func _ready() -> void:
	body_entered.connect(_eat)

func _eat(body: Node2D) -> void:
	# Two cells can arrive on the same frame, and queue_free() does not take the
	# node away until the end of it, so the second arrival has to be turned away
	# here or it frees an already-claimed nutrient.
	if is_queued_for_deletion():
		return
	# The dish wall is a body sitting on the prey's own layer, and it is not
	# hungry. Anything that is not a live cell simply is not eating.
	var cell := body as Cell
	if cell == null or cell.is_queued_for_deletion():
		return
	# A cell may turn the food down -- a ringer already carrying its protection
	# does. Refused food stays in the dish for whoever comes along next.
	if not cell.on_nutrient_eaten():
		return
	queue_free()
