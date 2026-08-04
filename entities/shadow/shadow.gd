class_name DropShadow
extends Sprite2D

## A flat silhouette of whatever it hangs under, slid away from the lamp. Purely
## cosmetic: it has no physics, casts no light and occludes nothing, so a shadow
## passing over another cell simply overlaps it.
##
## It copies the caster's texture and rotation every frame rather than once,
## because neither holds still -- the level hands out random textures at spawn
## and Cell spins its sprite continuously. Copying once would desync visibly.

## Where the lamp hangs, in world space, shared by every shadow so they all
## agree which way is away from it. The level writes these on startup.
static var light_position: Vector2 = Vector2.ZERO
## Constant drop every shadow gets. Without it, anything sitting directly under
## the lamp would have its shadow exactly behind it and look pasted flat.
static var base_offset: Vector2 = Vector2(18.0, 24.0)
## Extra slide per unit of distance from the lamp, which is what makes shadows
## fan outward across the dish. 0 leaves every shadow pointing the same way.
static var falloff: float = 0.012
## Cap, so cells out at the rim do not trail absurd shadows.
static var max_offset: float = 45.0

@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.35)
## Shadows a touch larger than the caster read as it floating above the dish
## rather than lying flat on it.
@export var size_scale: float = 1.05

@onready var _caster: Sprite2D = get_parent().get_node_or_null("Sprite2D")

func _ready() -> void:
	# Relative z_index, so this sits behind its own caster and behind every other
	# cell too. Cheaper and far less brittle than depending on child order.
	z_index = -1
	z_as_relative = true
	self_modulate = shadow_color
	if _caster == null:
		push_warning("DropShadow on %s found no sibling Sprite2D to copy." % get_parent().name)
		set_process(false)

func _process(_delta: float) -> void:
	if texture != _caster.texture:
		texture = _caster.texture
	rotation = _caster.rotation
	scale = _caster.scale * size_scale

	var anchor: Vector2 = _caster.global_position
	var slide: Vector2 = base_offset + (anchor - light_position) * falloff
	global_position = anchor + slide.limit_length(max_offset)
