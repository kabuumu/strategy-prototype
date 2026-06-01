extends Node
# Autoload singleton for sound effects. Loads the generated WAVs once and plays
# them through a small pool of AudioStreamPlayers so overlapping sounds work.

const NAMES: Array[String] = [
	"attack", "hit", "death", "heal", "ability",
	"capture", "gold", "stun", "win", "lose",
	"step", "select",
]
const POOL_SIZE: int = 8

# Aliases so call sites using other naming (from merged work) still play.
const ALIASES: Dictionary = {
	"kill": "death", "victory": "win", "defeat": "lose",
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for n: String in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for _i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(name: String, volume_db: float = -6.0) -> void:
	name = ALIASES.get(name, name)
	if not _streams.has(name):
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = volume_db
			p.play()
			return
	# All busy — reuse the first player
	_players[0].stream = _streams[name]
	_players[0].volume_db = volume_db
	_players[0].play()
