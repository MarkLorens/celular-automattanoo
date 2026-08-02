extends Camera2D

const CAMERA_SPEED = 500.0

func _process(delta):
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	position += direction * CAMERA_SPEED * delta
