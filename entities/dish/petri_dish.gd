@tool
class_name PetriDish
extends Node2D

## The edge of the world. One pair of radii drives the painted dish, the
## containing wall and the leash handed to every cell, so the three can never
## disagree.
##
## The glass is an oval rather than a circle so it fits the letterboxed frame the
## HUD is laid out around -- the gauge needs clear space down the side that a
## screen-filling circle would swallow.
##
## Everything outside is simply the black clear colour showing through: the dish
## is what gets painted, not the void around it.

## Horizontal inner radius of the glass. See leash_radii() for what the cells
## actually get.
@export var radius: float = 1700.0:
	set(value):
		radius = maxf(value, 0.0)
		_rebuild()

## Vertical radius as a fraction of the horizontal one. Below 1 gives the wide
## oval; exactly 1 restores a perfect circle.
@export var vertical_ratio: float = 0.73:
	set(value):
		vertical_ratio = maxf(value, 0.01)
		_rebuild()

## Cells start turning back this far inside the rim. Keep it above the cell
## collider radius (79px) so sprites do not poke through the glass.
@export var leash_margin: float = 150.0

## Wall resolution. 64 segments is smooth well past this scale.
@export var wall_segments: int = 64:
	set(value):
		wall_segments = maxi(value, 8)
		_rebuild()

@export_group("Look")
@export var background: Texture2D:
	set(value):
		background = value
		queue_redraw()
## Flat fill used when there is no background texture. The texture, when there
## is one, is drawn untinted -- this is the fallback, not a modulate.
@export var medium_color: Color = Color(0.09, 0.13, 0.13):
	set(value):
		medium_color = value
		queue_redraw()
@export var rim_color: Color = Color(0.60, 0.71, 0.74):
	set(value):
		rim_color = value
		queue_redraw()
@export var rim_width: float = 16.0:
	set(value):
		rim_width = value
		queue_redraw()
## Faint inner highlight, the meniscus where the medium meets the glass.
@export var meniscus_color: Color = Color(0.30, 0.42, 0.45, 0.35):
	set(value):
		meniscus_color = value
		queue_redraw()

@export_group("Temperature")
## Painted over the base background as the dish cools, from nothing at
## neutral_celsius to fully opaque at freeze_full_celsius.
@export var freeze_background: Texture2D:
	set(value):
		freeze_background = value
		queue_redraw()
## The heated counterpart, fading in as the dish warms past neutral_celsius.
@export var hot_background: Texture2D:
	set(value):
		hot_background = value
		queue_redraw()
## The temperature where neither overlay shows -- the midpoint the two fade out to.
@export var neutral_celsius: float = 50.0:
	set(value):
		neutral_celsius = value
		queue_redraw()
## The temperature at which freeze_background is fully opaque.
@export var freeze_full_celsius: float = 0.0:
	set(value):
		freeze_full_celsius = value
		queue_redraw()
## The temperature at which hot_background is fully opaque.
@export var hot_full_celsius: float = 100.0:
	set(value):
		hot_full_celsius = value
		queue_redraw()

## The dish's current heat, fed in by the level. Drives which overlay shows and
## how strongly. Starts at neutral so the dish is plain until the gauge speaks.
var temperature: float = 50.0:
	set(value):
		temperature = value
		queue_redraw()

func _ready() -> void:
	_rebuild()

## The two radii of the glass itself.
func radii() -> Vector2:
	return Vector2(radius, radius * vertical_ratio)

## The radii cells should treat as their boundary -- inside the glass, not on it.
func leash_radii() -> Vector2:
	var inner: Vector2 = radii() - Vector2(leash_margin, leash_margin)
	return Vector2(maxf(inner.x, 0.0), maxf(inner.y, 0.0))

func _rebuild() -> void:
	queue_redraw()
	var shape: CollisionPolygon2D = get_node_or_null("Wall/Shape")
	if shape == null:
		return  # Setter fired during scene load, before the children exist.
	shape.polygon = _oval(radii(), wall_segments)

func _draw() -> void:
	# An oval cannot be drawn with draw_circle/draw_arc, which only take a single
	# radius, so the medium becomes a filled polygon and the rings become closed
	# polylines around it.
	var outer: Vector2 = radii()
	 # draw_colored_polygon is the whole trick: hand it UVs and a texture and it
  # fills the oval with the image, clipped to the shape, in one call. No
  # viewport, no mask, no shader.
	var medium: PackedVector2Array = _oval(outer, wall_segments * 2)
	if background == null:
		draw_colored_polygon(medium, medium_color)
	else:
		draw_colored_polygon(medium, Color.WHITE, _cover_uvs(medium, outer, background), background)

	# The heat overlays sit over the base and under the glass, so the rim and
	# meniscus still read on top. Only the one matching the current temperature
	# carries any alpha; at neutral both are zero and nothing is drawn.
	_draw_cover(freeze_background, medium, outer, _freeze_alpha())
	_draw_cover(hot_background, medium, outer, _hot_alpha())

	if background != null:
		draw_polyline(_ring(outer - Vector2(rim_width, rim_width) * 1.0),
			meniscus_color, rim_width * 1.5, true)
	draw_polyline(_ring(outer - Vector2(rim_width, rim_width) * 0.5),
		rim_color, rim_width, true)

## Fills the oval with a texture at the given alpha, cover-fit exactly like the
## base background. A null texture or zero alpha draws nothing.
func _draw_cover(tex: Texture2D, points: PackedVector2Array, of_radii: Vector2, alpha: float) -> void:
	if tex == null or alpha <= 0.0:
		return
	draw_colored_polygon(points, Color(1.0, 1.0, 1.0, alpha), _cover_uvs(points, of_radii, tex), tex)

## 0 at neutral_celsius, ramping to 1 at hot_full_celsius. Clamped, so past the
## full point it simply stays opaque.
func _hot_alpha() -> float:
	var span: float = hot_full_celsius - neutral_celsius
	if is_zero_approx(span):
		return 0.0
	return clampf((temperature - neutral_celsius) / span, 0.0, 1.0)

## The mirror: 0 at neutral_celsius, ramping to 1 at freeze_full_celsius.
func _freeze_alpha() -> float:
	var span: float = neutral_celsius - freeze_full_celsius
	if is_zero_approx(span):
		return 0.0
	return clampf((neutral_celsius - temperature) / span, 0.0, 1.0)

## Points around an oval of these radii. Open, i.e. the first point is not
## repeated at the end -- which is what a polygon wants.
func _oval(of_radii: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		points.append(Vector2.RIGHT.rotated(TAU * i / float(segments)) * of_radii)
	return points

## The same ring closed back on itself, for stroking rather than filling.
func _ring(of_radii: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = _oval(of_radii, wall_segments * 2)
	points.append(points[0])
	return points

## UVs that make the background cover the oval without distorting it: centred,
## then scaled until it fills the bounding box, cropping whichever axis
## overflows. Mapping the box straight to 0..1 instead would squash a 16:9 image
## into the dish's 1.37:1 oval.
func _cover_uvs(points: PackedVector2Array, of_radii: Vector2, tex: Texture2D) -> PackedVector2Array:
	var source: Vector2 = tex.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return PackedVector2Array()
	var box: Vector2 = of_radii * 2.0
	var shown: Vector2 = source * maxf(box.x / source.x, box.y / source.y)
	var uvs := PackedVector2Array()
	for point in points:
		# Points are centred on the origin, so 0.5 puts the middle of the image
		# at the middle of the dish.
		uvs.append(Vector2(0.5, 0.5) + point / shown)
	return uvs
