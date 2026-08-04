class_name MenuDrift
extends Node2D

## The idle dish behind the title: cells and nutrients drifting across a black
## screen, so the menu reads as the thing the game is about rather than as a
## still image.
##
## Deliberately not real Cells. The live species carry flocking, predation and a
## pair of statics the whole dish shares (Cell.colonies, Cell.dish_celsius),
## none of which should be running behind a menu -- and none of which should be
## left dirtied for the level that follows. These are plain sprites with a
## velocity and nothing else, so the menu cannot reach into the game.
##
## Depth is faked from one roll per sprite: nearer ones are drawn bigger,
## brighter and drift faster, far ones small, dim and slow. It is the spread
## that sells it, so the ranges below want to stay wide.

## Everything that may appear, picked from at random per sprite. Left empty
## nothing spawns and the menu is simply black.
@export var textures: Array[Texture2D] = []
@export var count: int = 22

@export_group("Depth")
## On-screen size, longest edge in pixels, at the far and near ends of the roll.
## Sized in pixels rather than by sprite scale because the artwork is nothing
## like uniform -- a flocker is 128px and the mouser over 1000 -- so a shared
## scale would blow one species up and lose the other.
@export var far_size: float = 90.0
@export var near_size: float = 460.0
## Opacity at either end, so distance reads as haze and not only as size.
@export var far_alpha: float = 0.35
@export var near_alpha: float = 0.95
## Drift speed in px/s at either end. Near things crossing faster than far ones
## is the whole of the parallax.
@export var far_speed: float = 5.0
@export var near_speed: float = 26.0

@export_group("Spin")
## Radians per second, sampled either way so the scatter turns both directions.
@export var max_angular_speed: float = 0.25

## How far outside the screen a sprite runs before it is wrapped to the opposite
## edge. Comfortably past the largest of them, so nothing is seen popping across.
@export var wrap_margin: float = 320.0

# One drifting sprite plus the two things a Sprite2D does not carry itself.
class Drifter extends RefCounted:
	var sprite: Sprite2D
	var velocity: Vector2
	var spin: float

var _drifters: Array[Drifter] = []


func _ready() -> void:
	if textures.is_empty():
		return
	# Rolled up front and sorted so the sprites can be added far-to-near: draw
	# order is tree order, which puts the distant ones behind the close ones
	# without needing a z_index that would also have to be kept clear of the UI
	# drawn over the top of this.
	var depths := PackedFloat32Array()
	for i in count:
		depths.append(randf())
	depths.sort()
	for depth in depths:
		_drifters.append(_spawn_drifter(depth))


func _process(delta: float) -> void:
	var bounds: Vector2 = get_viewport_rect().size
	for drifter in _drifters:
		drifter.sprite.position = _wrapped(
			drifter.sprite.position + drifter.velocity * delta, bounds)
		drifter.sprite.rotation += drifter.spin * delta


## One sprite at this depth, 0 far and 1 near, dropped anywhere on screen. Its
## heading is free -- the scatter drifts every which way rather than sharing one
## current, which at these speeds reads as floating instead of as scrolling.
func _spawn_drifter(depth: float) -> Drifter:
	var drifter := Drifter.new()
	var texture: Texture2D = textures.pick_random()

	drifter.sprite = Sprite2D.new()
	drifter.sprite.texture = texture
	drifter.sprite.scale = Vector2.ONE * _scale_for(texture, lerpf(far_size, near_size, depth))
	drifter.sprite.modulate.a = lerpf(far_alpha, near_alpha, depth)
	drifter.sprite.rotation = randf() * TAU
	drifter.sprite.position = Vector2(
		randf() * get_viewport_rect().size.x,
		randf() * get_viewport_rect().size.y)

	drifter.velocity = Vector2.RIGHT.rotated(randf() * TAU) * lerpf(far_speed, near_speed, depth)
	drifter.spin = randf_range(-max_angular_speed, max_angular_speed)

	add_child(drifter.sprite)
	return drifter


## The scale that puts this texture's longest edge at `wanted` pixels, which is
## what lets one depth range govern artwork drawn at wildly different sizes.
func _scale_for(texture: Texture2D, wanted: float) -> float:
	var longest: float = maxf(texture.get_width(), texture.get_height())
	return wanted / maxf(longest, 1.0)


## Off one edge and back on the opposite one. The margin is what keeps the
## crossing out of sight: a sprite is wrapped only once it is well clear of the
## screen, rather than blinking across at the boundary.
func _wrapped(at: Vector2, bounds: Vector2) -> Vector2:
	return Vector2(
		wrapf(at.x, -wrap_margin, bounds.x + wrap_margin),
		wrapf(at.y, -wrap_margin, bounds.y + wrap_margin))
