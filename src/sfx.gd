extends Node

# Procedural sound effects — synthesised at startup so we don't need any
# external audio assets. Three short cues:
#   • "attack"  — quick wood-on-wood thud, played on every melee/ranged hit
#   • "kill"    — low boom played when a unit is defeated
#   • "victory" — major arpeggio C-E-G played on battle won
#
# Each sound is rendered into a PackedByteArray of 16-bit mono samples and
# wrapped in an AudioStreamWAV, then played through a dedicated
# AudioStreamPlayer so overlapping calls don't cut each other off.

const SR: int = 22050

var _players: Dictionary = {}

func _ready() -> void:
	_players["attack"]  = _make_player(_gen_attack(),  -6.0)
	_players["kill"]    = _make_player(_gen_kill(),    -3.0)
	_players["victory"] = _make_player(_gen_victory(), -4.0)

func play(sound_name: String) -> void:
	var p: AudioStreamPlayer = _players.get(sound_name)
	if p:
		p.play()

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
func _make_player(stream: AudioStreamWAV, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream     = stream
	p.volume_db  = vol_db
	add_child(p)
	return p

func _samples_to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: int = clampi(int(samples[i] * 32767.0), -32767, 32767)
		data.encode_s16(i * 2, v)
	var ws := AudioStreamWAV.new()
	ws.format    = AudioStreamWAV.FORMAT_16_BITS
	ws.mix_rate  = SR
	ws.stereo    = false
	ws.data      = data
	return ws

# 0.08s noise burst + body sine with exponential decay — wood-thud
func _gen_attack() -> AudioStreamWAV:
	var n: int = int(SR * 0.08)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t: float = float(i) / float(n)
		var env: float = exp(-t * 14.0)
		var v: float = (randf() * 2.0 - 1.0) * 0.4
		v += sin(2.0 * PI * 180.0 * float(i) / float(SR)) * 0.4
		s[i] = v * env
	return _samples_to_wav(s)

# 0.30s low boom — sweeping 120→60 Hz with noise grit
func _gen_kill() -> AudioStreamWAV:
	var n: int = int(SR * 0.30)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t: float = float(i) / float(n)
		var env: float = exp(-t * 4.5)
		var freq: float = 120.0 - 60.0 * t
		var v: float = sin(2.0 * PI * freq * float(i) / float(SR)) * 0.7
		v += (randf() * 2.0 - 1.0) * 0.15 * env
		s[i] = v * env
	return _samples_to_wav(s)

# 0.54s ascending major arpeggio C5-E5-G5 (523/659/784 Hz)
func _gen_victory() -> AudioStreamWAV:
	var freqs: Array[float] = [523.0, 659.0, 784.0]
	var seg: int = int(SR * 0.18)
	var s := PackedFloat32Array()
	s.resize(seg * freqs.size())
	for k in range(freqs.size()):
		var f: float = freqs[k]
		for i in range(seg):
			var t: float = float(i) / float(seg)
			var env: float = sin(PI * t)
			var v: float = sin(2.0 * PI * f * float(i) / float(SR)) * 0.5
			s[k * seg + i] = v * env
	return _samples_to_wav(s)
