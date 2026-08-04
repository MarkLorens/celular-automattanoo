extends Control

@onready var timer_label = $Label

var total_time: float = 0.000
var final_time: float = 0.000


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	total_time += delta
	timer_label.text = "%.0f" % total_time

func stop() -> void:
	final_time = total_time
