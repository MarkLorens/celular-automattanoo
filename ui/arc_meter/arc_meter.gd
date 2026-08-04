class_name ArcMeter
extends Control

## Curved segmented slider for the HUD. Sits on an arc whose centre is off to
## one side, so the bars bow around the dish rather than running straight up.
##
## Everything is drawn rather than textured, the same way PetriDish draws its
## glass -- the shape is entirely described by the exports below, so retuning it
## is a matter of numbers instead of new art.
##
## Fill runs from start_angle to end_angle. The colour comes from one gradient
## sampled across the whole meter rather than per bar, so it flows through the
## gaps instead of restarting in each one, and anything past the fill line is
## drawn in empty_color.

signal value_changed(value: float)

@export_group("Value")
## 0 is empty and entirely grey, 1 is full and entirely coloured.
@export_range(0.0, 1.0, 0.001) var value: float = 0.0:
	set = set_value

@export_group("Shape")
## Centre of the circle the bars are cut from, in this control's own space. Well
## off to the right of the bars themselves, which is what bows them around the dish.
@export var arc_center: Vector2 = Vector2(960.0, 620.0)
@export var radius: float = 780.0
@export var thickness: float = 80.0
## The empty end of the meter, where filling starts. Godot angles run clockwise
## from +X with Y pointing down, so ~149 degrees is the lower left of a circle.
@export var start_angle_degrees: float = 149.0
## The full end. ~226 degrees is the upper left, so the meter fills upward.
@export var end_angle_degrees: float = 226.0
@export var segments: int = 3
## Angular gap between bars.
@export var gap_degrees: float = 4.0
## Points drawn per bar. Enough that the curve reads smooth and the gradient
## does not band.
@export var resolution: int = 48

@export_group("Colour")
## Sampled across the whole meter, 0 at the empty end. Left unset, the built-in
## indigo to crimson ramp is used.
@export var fill_gradient: Gradient
## What an unfilled stretch of bar looks like.
@export var empty_color: Color = Color(0.22, 0.23, 0.27, 0.9)

@export_group("Input")
## How far either side of the bar still counts as grabbing it, so the meter does
## not demand pixel accuracy.
@export var grab_padding: float = 26.0

var _dragging: bool = false

func _ready() -> void:
	if fill_gradient == null:
		fill_gradient = _default_gradient()
	set_process(false)

func set_value(new_value: float) -> void:
	var clamped: float = clampf(new_value, 0.0, 1.0)
	if is_equal_approx(clamped, value):
		return
	value = clamped
	queue_redraw()
	value_changed.emit(value)

func _draw() -> void:
	var span: float = _span()
	var gap: float = deg_to_rad(gap_degrees)
	var bar_span: float = (span - gap * (segments - 1)) / float(maxi(segments, 1))
	if bar_span <= 0.0:
		return  # More gap than meter; nothing sensible to draw.

	var start: float = deg_to_rad(start_angle_degrees)
	for bar in segments:
		var bar_start: float = start + bar * (bar_span + gap)
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for step in resolution + 1:
			var angle: float = bar_start + bar_span * (float(step) / float(resolution))
			# Position along the whole meter, not along this bar, so the ramp
			# carries across the gaps.
			var along: float = (angle - start) / span
			points.append(arc_center + Vector2.RIGHT.rotated(angle) * radius)
			colors.append(fill_gradient.sample(along) if along <= value else empty_color)
		draw_polyline_colors(points, colors, thickness, true)

## Restricts the control's hit area to the bars themselves. Without this the
## meter would be a screen-sized rectangle quietly eating every click that
## landed anywhere near it.
func _has_point(point: Vector2) -> bool:
	var offset: Vector2 = point - arc_center
	if absf(offset.length() - radius) > thickness * 0.5 + grab_padding:
		return false
	var along: float = _position_along(point)
	return along >= -0.05 and along <= 1.05

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	_dragging = true
	set_process(true)
	set_value(clampf(_position_along(button.position), 0.0, 1.0))
	accept_event()

# Polling beats waiting for motion events here: the pointer routinely leaves the
# bar mid-drag, and a grab that died the moment it did would be unusable.
func _process(_delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
		set_process(false)
		return
	set_value(clampf(_position_along(get_local_mouse_position()), 0.0, 1.0))

func _span() -> float:
	return deg_to_rad(end_angle_degrees - start_angle_degrees)

## Where a point sits along the meter: 0 at the empty end, 1 at the full end,
## outside that range when it is past either end. Wrapped to the nearest turn so
## an arc that straddles the +/-PI seam still measures correctly.
func _position_along(point: Vector2) -> float:
	var span: float = _span()
	if is_zero_approx(span):
		return 0.0
	var offset: Vector2 = point - arc_center
	return wrapf(offset.angle() - deg_to_rad(start_angle_degrees), -PI, PI) / span

## Indigo at the empty end through magenta to crimson at the full end.
func _default_gradient() -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.29, 0.35, 0.85),
		Color(0.85, 0.20, 0.55),
		Color(0.80, 0.12, 0.25),
	])
	return ramp
