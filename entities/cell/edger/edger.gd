class_name Edger
extends Cell

## Lives on the glass. An edger makes straight for the dish wall and stays
## pressed against it, so the colony reads as a ring around the rim rather than
## as anything spread through the medium.
##
## It does not queue and it does not take turns. Every edger wants the wall,
## separation (from Cell) is all that keeps them off each other, and the two
## together mean a crowded stretch of rim genuinely jams: the ones behind are
## stuck until the ones in front drift along. That is the shape of the species
## rather than a failure of the steering, so nothing here tries to resolve it.
##
## Cold is its element. Heat past lethal_above_celsius kills it where it floats,
## and below thrives_below_celsius the colony breeds half again as fast. A
## nutrient buys a shorter spell of the same thing.

@export_group("Edge Seeking")
## Weight of the outward pull. Reads against Cell's containment_weight, which is
## what turns an edger back at the leash -- the two together are what settle it
## against the glass instead of driving it through.
@export var edge_weight: float = 2.2

@export_group("Temperature")
## Past this the dish is too warm to survive and the edger dies where it floats.
@export var lethal_above_celsius: float = 50.0
## Below this the colony breeds faster, by cold_breeding_rate.
@export var thrives_below_celsius: float = 10.0
@export var cold_breeding_rate: float = 1.5

@export_group("Reproduction")
## What a nutrient is worth: this much extra breeding rate, for this long.
@export var nutrient_breeding_rate: float = 1.2
@export var nutrient_boost_duration: float = 30.0

# Seconds left on the colony's nutrient boost. Static because the boost belongs
# to the colony and not to the cell that ate: edgers arrive on the level's drip
# feed, which is one clock for the whole species, so there is nothing for a
# per-cell boost to speed up.
static var _boost_remaining: float = 0.0
# Which physics frame that shared clock was last run down on. Without it every
# edger alive would take its own delta off the same countdown, and a rim of
# twenty would burn thirty seconds of boost in a second and a half.
static var _boost_frame: int = -1


func _ready() -> void:
	super()  # GDScript does not chain _ready(); without this Cell's never runs.
	add_to_group("edger")
	add_to_group(FLOATER_GROUP)
	# Statics outlive a scene reload, so the first edger of a run clears whatever
	# the last one left behind -- otherwise a retry could open part-boosted.
	# _enter_tree() has already filed this cell, so a colony of one is a colony
	# that has only just started.
	if _colony.size() <= 1:
		_boost_remaining = 0.0


func _physics_process(delta: float) -> void:
	_tick_boost(delta)
	if dish_celsius > lethal_above_celsius:
		# Cooked. Steering a corpse for one more frame would only have it drift
		# after it was already dead, so this returns rather than falling through.
		queue_free()
		return
	super(delta)  # Only the most derived _physics_process is called.


## Read by the level to pace this colony's drip feed: the multiple of its normal
## rate the edgers are currently breeding at. Cold and a recent nutrient both
## quicken it and the two compound, so a chilled dish that has just been fed
## fills its rim faster than either would on its own.
func breeding_rate() -> float:
	var rate: float = 1.0
	if dish_celsius < thrives_below_celsius:
		rate *= cold_breeding_rate
	if _boost_remaining > 0.0:
		rate *= nutrient_breeding_rate
	return rate


## A nutrient feeds the colony rather than this one edger. The spell is started
## afresh rather than added to, so a hoard of food cannot be banked up into one
## enormous boost -- eating early only means it lapses earlier.
func on_nutrient_eaten() -> bool:
	_boost_remaining = nutrient_boost_duration
	Audio.play_sfx(eat_sound)
	return true


## Runs the shared clock down once a frame, by whichever edger reaches it first.
static func _tick_boost(delta: float) -> void:
	var frame: int = Engine.get_physics_frames()
	if frame == _boost_frame:
		return
	_boost_frame = frame
	_boost_remaining = maxf(_boost_remaining - delta, 0.0)


func _steering(_delta: float) -> Vector2:
	# Measured in leash-widths, the same trick Cell's containment uses: scaling
	# the space by the leash radii turns the oval boundary back into a circle,
	# and the way out of a circle is simply straight from the middle. Steering on
	# the raw offset instead would send every edger to the nearest glass, which
	# on a dish this wide means piling into the top and bottom of it.
	var reach: Vector2 = roam_reach()
	var outward: Vector2 = (global_position - roam_center) / reach
	if outward.is_zero_approx():
		# Dead centre, where no way out is more outward than any other.
		outward = Vector2.RIGHT.rotated(randf() * TAU)
	# Back into world space, which is what the steering has to be expressed in.
	# _steer_toward reads only the direction, so the length here does not matter.
	return _steer_toward(outward.normalized() * reach) * edge_weight
