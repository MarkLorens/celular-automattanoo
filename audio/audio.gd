extends Node

## Audio that has to outlive scene changes lives on this "Audio" autoload: the
## looping music bed, which must play unbroken from the menu into a run, and a
## small round-robin pool of one-shot voices for SFX that may overlap -- a cluster
## of cells eaten in the same instant would otherwise cut each other off.

const SFX_VOICES := 8

@onready var _music: AudioStreamPlayer = $Music

var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_voice: int = 0


func _ready() -> void:
	# ALWAYS, so the music keeps going while the tree is paused behind the title
	# card -- a paused autoload would fall silent the moment the level froze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_sfx_pool.append(voice)
	play_music()


## Starts the music unless it is already going. Idempotent on purpose: the level
## calls it on load, but arriving from the menu the track is already playing and
## must not restart mid-phrase. After a game over stops it, this brings it back.
func play_music() -> void:
	if _music.stream != null and not _music.playing:
		_music.play()


func stop_music() -> void:
	_music.stop()


## Plays a one-shot on the next voice, round-robin, so overlapping sounds layer
## instead of interrupting. A null stream is ignored, so an unassigned eat_sound
## simply makes no noise.
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var voice: AudioStreamPlayer = _sfx_pool[_next_voice]
	_next_voice = (_next_voice + 1) % _sfx_pool.size()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.play()
