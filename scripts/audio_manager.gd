extends Node

# AudioManager Autoload (res://scripts/audio_manager.gd)
# Features 100% Halal / clean instrumental cyber synth soundtrack and procedural SFX,
# with real-time volume sliders, mute toggle, and configuration persistence.

signal settings_changed(music_vol: float, sfx_vol: float, is_muted: bool)

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

var music_volume: float = 0.65 # 0.0 - 1.0
var sfx_volume: float = 0.8    # 0.0 - 1.0
var is_muted: bool = false

const SETTINGS_PATH: String = "user://audio_settings.cfg"

var bgm_stream: AudioStreamWAV = null
var sfx_library: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)
	
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "Master"
	add_child(sfx_player)
	
	load_audio_settings()
	_generate_bgm_track()
	_generate_sfx_library()
	
	apply_volumes()
	play_bgm()

func load_audio_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_volume = cfg.get_value("audio", "music_volume", 0.65)
		sfx_volume = cfg.get_value("audio", "sfx_volume", 0.8)
		is_muted = cfg.get_value("audio", "is_muted", false)

func save_audio_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "is_muted", is_muted)
	cfg.save(SETTINGS_PATH)

func set_music_volume(val: float) -> void:
	music_volume = clampf(val, 0.0, 1.0)
	apply_volumes()
	save_audio_settings()
	settings_changed.emit(music_volume, sfx_volume, is_muted)

func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	apply_volumes()
	save_audio_settings()
	settings_changed.emit(music_volume, sfx_volume, is_muted)

func set_muted(mute: bool) -> void:
	is_muted = mute
	apply_volumes()
	save_audio_settings()
	settings_changed.emit(music_volume, sfx_volume, is_muted)

func apply_volumes() -> void:
	if is_muted:
		if music_player:
			music_player.volume_db = -80.0
		if sfx_player:
			sfx_player.volume_db = -80.0
	else:
		if music_player:
			music_player.volume_db = linear_to_db(maxf(music_volume, 0.0001))
		if sfx_player:
			sfx_player.volume_db = linear_to_db(maxf(sfx_volume, 0.0001))

func play_bgm() -> void:
	if music_player and bgm_stream:
		if not music_player.playing:
			music_player.stream = bgm_stream
			music_player.play()

func stop_bgm() -> void:
	if music_player:
		music_player.stop()

func play_sfx(sfx_name: String) -> void:
	if is_muted or sfx_volume <= 0.01:
		return
	if sfx_library.has(sfx_name) and sfx_player:
		sfx_player.stream = sfx_library[sfx_name]
		sfx_player.play()

# Generate ambient cyber synth loop (100% Halal / clean synthesizer harmonic game track)
func _generate_bgm_track() -> void:
	var sample_rate = 22050
	var bpm = 120.0
	var beat_duration = 60.0 / bpm
	var total_beats = 16.0 # 4 bars of 4/4
	var duration = total_beats * beat_duration
	var total_samples = int(duration * sample_rate)
	
	# Scale chords (Cyber Dorian: D, F, G, A, C)
	var chord_roots = [146.83, 174.61, 130.81, 164.81] # D3, F3, C3, E3
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2) # 16-bit mono
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var beat_num = t / beat_duration
		var bar_num = int(beat_num / 4.0) % chord_roots.size()
		var root_freq = chord_roots[bar_num]
		
		# Arpeggio note selector
		var arp_step = int(beat_num * 4.0) % 8
		var arp_mult = 1.0
		match arp_step:
			0: arp_mult = 1.0
			1: arp_mult = 1.25 # minor 3rd approx / fifth
			2: arp_mult = 1.5  # perfect 5th
			3: arp_mult = 2.0  # octave
			4: arp_mult = 1.5
			5: arp_mult = 1.75
			6: arp_mult = 1.25
			7: arp_mult = 2.0
		
		var arp_freq = root_freq * arp_mult
		
		# Ambient Bass + Arp + Soft rhythmic pulse
		var bass = sin(2.0 * PI * (root_freq * 0.5) * t) * 0.35
		var arp = sin(2.0 * PI * arp_freq * t) * 0.25
		# Soft sub pad
		var pad = sin(2.0 * PI * (root_freq * 1.5) * t) * 0.15
		
		# Soft synth rhythm pulse (decay envelope per beat)
		var beat_fract = fmod(beat_num, 1.0)
		var pulse_env = exp(-beat_fract * 4.0)
		var pulse = sin(2.0 * PI * 65.4 * t) * pulse_env * 0.2
		
		var mixed = (bass + arp + pad + pulse) * 0.4
		mixed = clampf(mixed, -0.95, 0.95)
		var sample_int = int(mixed * 32767.0)
		
		# 16-bit little-endian
		var u_sample = sample_int if sample_int >= 0 else (65536 + sample_int)
		byte_array.encode_u16(i * 2, u_sample)
	
	bgm_stream = AudioStreamWAV.new()
	bgm_stream.format = AudioStreamWAV.FORMAT_16_BITS
	bgm_stream.mix_rate = sample_rate
	bgm_stream.stereo = false
	bgm_stream.data = byte_array
	bgm_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bgm_stream.loop_begin = 0
	bgm_stream.loop_end = total_samples

func _generate_sfx_library() -> void:
	sfx_library["click"] = _generate_tone(440.0, 0.05, 0.2)
	sfx_library["success"] = _generate_success_chime()
	sfx_library["error"] = _generate_tone(160.0, 0.18, 0.3)
	sfx_library["redeem"] = _generate_redeem_fanfare()

func _generate_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(duration * sample_rate)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var env = 1.0 - (float(i) / float(total_samples))
		var wave = sin(2.0 * PI * freq * t) * env * volume
		var sample_int = int(clampf(wave, -1.0, 1.0) * 32767.0)
		var u_sample = sample_int if sample_int >= 0 else (65536 + sample_int)
		byte_array.encode_u16(i * 2, u_sample)
	
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = byte_array
	return wav

func _generate_success_chime() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.35
	var total_samples = int(duration * sample_rate)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var env = exp(-t * 8.0)
		# Ascending arpeggio chime (523Hz -> 659Hz -> 783Hz)
		var freq = 523.25
		if t > 0.1: freq = 659.25
		if t > 0.2: freq = 783.99
		var wave = sin(2.0 * PI * freq * t) * env * 0.3
		var sample_int = int(clampf(wave, -1.0, 1.0) * 32767.0)
		var u_sample = sample_int if sample_int >= 0 else (65536 + sample_int)
		byte_array.encode_u16(i * 2, u_sample)
	
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = byte_array
	return wav

func _generate_redeem_fanfare() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.6
	var total_samples = int(duration * sample_rate)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var env = exp(-t * 3.5)
		var freq = 440.0
		if t > 0.12: freq = 554.37 # C#5
		if t > 0.24: freq = 659.25 # E5
		if t > 0.36: freq = 880.00 # A5
		var wave = (sin(2.0 * PI * freq * t) + 0.5 * sin(2.0 * PI * freq * 2.0 * t)) * env * 0.3
		var sample_int = int(clampf(wave, -1.0, 1.0) * 32767.0)
		var u_sample = sample_int if sample_int >= 0 else (65536 + sample_int)
		byte_array.encode_u16(i * 2, u_sample)
	
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = byte_array
	return wav

