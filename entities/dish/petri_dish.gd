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
	draw_colored_polygon(_oval(outer, wall_segments * 2), medium_color)
	draw_polyline(_ring(outer - Vector2(rim_width, rim_width) * 1.0),
		meniscus_color, rim_width * 1.5, true)
	draw_polyline(_ring(outer - Vector2(rim_width, rim_width) * 0.5),
		rim_color, rim_width, true)

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
