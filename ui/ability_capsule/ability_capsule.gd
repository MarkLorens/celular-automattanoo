class_name AbilityCapsule
extends Control

## A right-of-the-dish instruction pill: the key that fires an ability drawn over
## a scrap of the thing it summons, clipped to the capsule shape. Purely a readout
## -- it takes no input. The level greys it while its ability is still locked and
## clears the grey the moment enough play time has passed to unlock it.

## The input action this pill illustrates. The level matches it to an ability so
## it knows when to un-grey the pill.
@export var action: StringName = &""

## The key the player presses, drawn big over the image.
@export var letter: String = "":
	set(value):
		letter = value
		if is_node_ready():
			_letter_label.text = value

## The scrap shown inside the pill, clipped to its shape. It need not fit -- the
## capsule mask crops whatever spills past the edge.
@export var image: Texture2D:
	set(value):
		image = value
		if is_node_ready():
			_image_rect.texture = value

## The dim tint worn until the ability unlocks.
@export var locked_tint: Color = Color(0.5, 0.5, 0.55, 0.8)

@onready var _image_rect: TextureRect = $Mask/Image
@onready var _letter_label: Label = $Mask/Letter

# Starts locked; the level flips it on the first frame once it knows the clock.
var _locked: bool = true


func _ready() -> void:
	_image_rect.texture = image
	_letter_label.text = letter
	modulate = locked_tint if _locked else Color.WHITE


## Greys the pill (locked) or restores it (unlocked). Cheap to call every frame:
## nothing happens unless the state actually flips.
func set_locked(locked: bool) -> void:
	if locked == _locked:
		return
	_locked = locked
	modulate = locked_tint if locked else Color.WHITE
