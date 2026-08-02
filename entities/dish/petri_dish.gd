@tool
class_name PetriDish
extends Node2D

## The edge of the world. One radius drives the painted dish, the containing
## wall and the leash handed to every cell, so the three can never disagree.
##
## Everything outside is simply the black clear colour showing through -- the
## dish is what gets painted, not the void around it.

## Inner edge of the glass. See leash_radius() for what the cells actually get.
@export var radius: float = 1300.0:
	set(value):
		radius = maxf(value, 0.0)
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

## The radius cells should treat as their boundary -- inside the glass, not on it.
func leash_radius() -> float:
	return maxf(radius - leash_margin, 0.0)

func _rebuild() -> void:
	queue_redraw()
	var shape: CollisionPolygon2D = get_node_or_null("Wall/Shape")
	if shape == null:
		return  # Setter fired during scene load, before the children exist.
	var points := PackedVector2Array()
	for i in wall_segments:
		points.append(Vector2.RIGHT.rotated(TAU * i / float(wall_segments)) * radius)
	shape.polygon = points

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, medium_color, true, -1.0, true)
	draw_arc(Vector2.ZERO, radius - rim_width, 0.0, TAU, wall_segments * 2,
		meniscus_color, rim_width * 1.5, true)
	draw_arc(Vector2.ZERO, radius - rim_width * 0.5, 0.0, TAU, wall_segments * 2,
		rim_color, rim_width, true)
