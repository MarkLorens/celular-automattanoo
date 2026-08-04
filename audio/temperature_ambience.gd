class_name TemperatureAmbience
extends Node

## Four looping ambient beds tied to the dish temperature. All play at once; the
## bed at the current temperature is loudest and its neighbours fade in around it
## -- the same crossfade the background overlays use -- so the room's tone slides
## with the gauge instead of snapping between clips. At exactly a threshold only
## that one bed is heard.

## Index-aligned with the bed children below: the temperature each one owns.
@export var thresholds: PackedFloat32Array = PackedFloat32Array([0.0, 30.0, 60.0, 100.0])
## The volume a bed reaches when the temperature sits right on its threshold.
@export var full_volume_db: float = 6.0
## Beneath this linear weight a bed is cut to silence rather than left mixing in
## at an inaudible whisper.
@export var silence_below: float = 0.02

@onready var _beds: Array = [$Bed0, $Bed30, $Bed60, $Bed100]


func _ready() -> void:
	# ALWAYS so the beds keep looping while the tree is paused behind the title
	# card; game_over stops them explicitly when the run ends.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Started once and never restarted, so each bed's .wav has to import with
	# `edit/loop_mode=2` (Forward). That importer setting is an enum, not a
	# boolean -- 1 is Disabled, which silently played every bed through once and
	# left the dish silent for the rest of the run.
	for bed in _beds:
		if bed.stream != null:
			bed.play()


## Rebalances every bed for this temperature. Cheap -- called whenever the gauge
## moves, and once at startup.
func set_temperature(celsius: float) -> void:
	for i in _beds.size():
		var weight: float = _weight_for(i, celsius)
		var bed: AudioStreamPlayer = _beds[i]
		bed.volume_db = -80.0 if weight <= silence_below else full_volume_db + linear_to_db(weight)


func stop() -> void:
	for bed in _beds:
		bed.stop()


## How strongly bed `index` sounds at this temperature: 1 right on its threshold,
## easing to 0 at each neighbour, and held flat past the ends so the coldest and
## hottest beds do not fade out beyond their own extremes.
func _weight_for(index: int, celsius: float) -> float:
	var here: float = thresholds[index]
	if index == 0 and celsius <= here:
		return 1.0
	if index == _beds.size() - 1 and celsius >= here:
		return 1.0
	# Ramp up from the neighbour below.
	if index > 0:
		var below: float = thresholds[index - 1]
		if celsius >= below and celsius <= here:
			return (celsius - below) / (here - below)
	# Ramp down toward the neighbour above.
	if index < _beds.size() - 1:
		var above: float = thresholds[index + 1]
		if celsius >= here and celsius <= above:
			return (above - celsius) / (above - here)
	return 0.0
