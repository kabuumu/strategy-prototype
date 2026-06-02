extends Node

# Background music autoload. Loops a track per scene and persists across scene
# changes; asking for a track whose file is already playing is a no-op (no
# restart). Volume rides the Master bus, so the title's volume slider controls it.

const TRACKS: Dictionary = {
	"title":  "res://assets/music/cathedral_rust_chant.mp3",
	"map":    "res://assets/music/cathedral_rust_chant.mp3",
	"battle": "res://assets/music/cathedral_rust_chant.mp3",
}

var _player: AudioStreamPlayer
var _current: String = ""   # the currently-playing file path

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = -9.0   # sit under the SFX
	add_child(_player)

func play(track: String) -> void:
	if not TRACKS.has(track):
		return
	var path: String = TRACKS[track]
	if path == _current and _player.playing:
		return   # same file already playing — don't restart on scene change
	var stream = load(path)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.data.size() / 2)   # mono 16-bit -> 2 bytes/frame
	elif stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	_current = path
	_player.stream = stream
	_player.play()

func stop() -> void:
	_current = ""
	if _player != null:
		_player.stop()
