class_name AbilityCapsule
extends Control

## A right-of-the-dish instruction pill: the key that fires an ability drawn over
## a scrap of the thing it summons, clipped to the capsule shape. Purely a readout
## -- it takes no input. The level greys it while its ability is still locked and
## clears the grey the moment enough play time has passed to unlock it.
##
## Recharging is shown the same way but in miniature: a grey pane fills the pill
## the instant the ability fires and drains off as the cooldown runs down, so how
## much longer there is to wait is readable at a glance rather than being a flat
## on/off dimming. Locked and cooling are separate states and can overlap without
## fighting -- the lock tints the whole pill, the cooldown is one child inside it.

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

@export_group("Cooldown")
## The grey the recharging pane is painted in. Deliberately part-transparent: a
## cooling ability should read as dimmed rather than blanked out, so the player
## can still see which ability it is they are waiting on.
@export var cooldown_tint: Color = Color(0.12, 0.13, 0.16, 0.55)
## Which way the grey goes as it drains. On, it pools at the bottom and its level
## falls as the ability recharges; off, it hangs from the top and lifts away.
@export var drain_downward: bool = true

@onready var _mask: Panel = $Mask
@onready var _image_rect: TextureRect = $Mask/Image
@onready var _letter_label: Label = $Mask/Letter
@onready var _cooldown_rect: ColorRect = $Mask/Cooldown

# Starts locked; the level flips it on the first frame once it knows the clock.
var _locked: bool = true


func _ready() -> void:
	_image_rect.texture = image
	_letter_label.text = letter
	modulate = locked_tint if _locked else Color.WHITE
	_cooldown_rect.color = cooldown_tint
	set_cooldown(0.0)


## Greys the pill (locked) or restores it (unlocked). Cheap to call every frame:
## nothing happens unless the state actually flips.
func set_locked(locked: bool) -> void:
	if locked == _locked:
		return
	_locked = locked
	modulate = locked_tint if locked else Color.WHITE


## How much of the recharge is still to go: 1 the instant the ability fires, 0
## once it is ready again. Sizes the grey pane to match, so passing the level's
## remaining/total straight in drains it in step with the cooldown.
##
## The pane is positioned rather than anchored. Setting an anchor from code
## rewrites the offsets to hold the control still, so driving the edge by anchor
## would leave the pane exactly where it was; a plain position and size is what
## actually moves it. It is clipped to the pill by the Mask either way.
func set_cooldown(remaining: float) -> void:
	var fraction: float = clampf(remaining, 0.0, 1.0)
	_cooldown_rect.visible = fraction > 0.0
	if not _cooldown_rect.visible:
		return
	var full: Vector2 = _mask.size
	var height: float = full.y * fraction
	_cooldown_rect.position = Vector2(0.0, full.y - height if drain_downward else 0.0)
	_cooldown_rect.size = Vector2(full.x, height)
