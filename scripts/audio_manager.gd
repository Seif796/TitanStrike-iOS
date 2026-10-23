extends Node

# AudioManager Autoload (res://scripts/audio_manager.gd)
# Features 100% Halal / clean high-fidelity stereo cyber ambient synth soundtrack (44.1 kHz),
# with lush analog pads, melodic arpeggios, warm sub-bass, and procedural SFX.

signal settings_changed(music_vol: float, sfx_vol: float, is_muted: bool)

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

var music_volume: float = 0.42 # 0.0 - 1.0
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
		music_volume = cfg.get_value("audio", "music_volume", 0.42)
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

# Generate high-fidelity lush stereo cyber soundtrack (44.1 kHz, 16-bit Stereo)
# Rich ambient pad harmony (Am - F - C - G) with warm sub-bass and crystal bells
func toggle_mute() -> void:
	set_muted(not is_muted)

func toggle_bgm() -> void:
	if music_player and music_player.playing:
		stop_bgm()
	else:
		play_bgm()

# ==============================================================================
# BRAND NEW CYBERPUNK SYNTHWAVE SOUNDTRACK (8-Bar Epic Melodic Theme, 118 BPM)
# Featuring warm analog sub-bass, lush stereo pads, heroic cyber lead, and rhythmic groove.
# ==============================================================================
func _generate_bgm_track() -> void:
	var sample_rate: int = 44100
	var bpm: float = 118.0
	var beat_duration: float = 60.0 / bpm
	var total_beats: float = 32.0 # 8 full bars (4/4 time)
	var duration: float = total_beats * beat_duration
	var total_samples: int = int(duration * sample_rate)
	
	# 8-Bar Chord Progression: Am -> Fmaj7 -> Dm7 -> Em / G
	var chords = [
		{"root": 220.00, "third": 261.63, "fifth": 329.63, "bass": 55.00},  # Am (Bars 0-1)
		{"root": 220.00, "third": 261.63, "fifth": 329.63, "bass": 55.00},
		{"root": 174.61, "third": 220.00, "fifth": 261.63, "bass": 43.65},  # Fmaj (Bars 2-3)
		{"root": 174.61, "third": 220.00, "fifth": 261.63, "bass": 43.65},
		{"root": 146.83, "third": 174.61, "fifth": 220.00, "bass": 36.71},  # Dm (Bars 4-5)
		{"root": 146.83, "third": 174.61, "fifth": 220.00, "bass": 36.71},
		{"root": 196.00, "third": 246.94, "fifth": 293.66, "bass": 49.00},  # G / Em (Bars 6-7)
		{"root": 164.81, "third": 196.00, "fifth": 246.94, "bass": 41.20}
	]
	
	# 32-Beat Heroic Melodic Lead Theme (Semitone offsets relative to A4 = 440Hz)
	var melody_notes = [
		0,   0,   3,   5,   7,   7,   5,   3,  # Bar 0-1: Theme statement
		0,  -2,   0,   3,   5,   5,   7,   8,  # Bar 2-3: Rising tension
		7,   5,   3,   5,   7,  10,   8,   7,  # Bar 4-5: Heroic apex
		5,   3,   2,   3,   5,   3,   2,   0   # Bar 6-7: Graceful cyber resolution
	]
	
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 4)
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var beat_num = t / beat_duration
		var bar_num = int(beat_num / 4.0) % chords.size()
		var chord = chords[bar_num]
		
		# 1. Warm Analog Stereo Pad (Rich detuned saws smoothed with sine modulation)
		var pad_osc1 = sin(2.0 * PI * chord["root"] * t) + 0.5 * sin(2.0 * PI * chord["third"] * t) + 0.4 * sin(2.0 * PI * chord["fifth"] * t)
		var pad_osc2 = sin(2.0 * PI * (chord["root"] * 1.003) * t) + 0.5 * sin(2.0 * PI * (chord["third"] * 0.997) * t) + 0.4 * sin(2.0 * PI * (chord["fifth"] * 1.002) * t)
		
		# Bar swell envelope for organic breathing
		var bar_progress = fmod(beat_num, 4.0) / 4.0
		var swell = 0.75 + 0.25 * sin(bar_progress * PI)
		var pad_l = pad_osc1 * swell * 0.14
		var pad_r = pad_osc2 * swell * 0.14
		
		# 2. Driving 8th-Note Cyber Bassline (Rhythmic, warm, punchy)
		var sub_step = fmod(beat_num * 2.0, 1.0)
		var bass_env = exp(-sub_step * 5.0) # Tight rhythmic pluck
		var bass_octave = 1.0 if fmod(floor(beat_num * 2.0), 2.0) == 0.0 else 2.0
		var bass_freq = chord["bass"] * bass_octave
		var bass = (sin(2.0 * PI * bass_freq * t) + 0.3 * sin(2.0 * PI * (bass_freq * 2.0) * t)) * bass_env * 0.24
		
		# 3. Heroic Cyber Lead Melody (Lush vibrato & tape delay)
		var mel_idx = int(beat_num) % melody_notes.size()
		var mel_semi = melody_notes[mel_idx]
		var mel_freq = 440.0 * pow(2.0, float(mel_semi) / 12.0)
		
		var mel_step = fmod(beat_num, 1.0)
		var mel_env = exp(-mel_step * 3.0) # Smooth flute-synth decay
		var vibrato = 1.0 + 0.008 * sin(2.0 * PI * 5.5 * t)
		var lead_tone = (sin(2.0 * PI * mel_freq * vibrato * t) + 0.25 * sin(2.0 * PI * (mel_freq * 2.0) * t)) * mel_env * 0.18
		
		# Gentle ping-pong stereo delay for the lead
		var lead_l = lead_tone * 0.65
		var lead_r = lead_tone * 0.45
		
		# 4. Subtle Electronic Sidechain Groove (Ducks slightly on the quarter beat for modern punch)
		var beat_pulse = fmod(beat_num, 1.0)
		var sidechain = 0.82 + 0.18 * smoothstep(0.0, 0.4, beat_pulse)
		
		# Combine Left & Right Channels
		var out_l = ((pad_l + bass) * sidechain) + lead_l
		var out_r = ((pad_r + bass) * sidechain) + lead_r
		
		# Soft-clipping master limiter
		out_l = clampf(out_l * 0.58, -0.85, 0.85)
		out_r = clampf(out_r * 0.58, -0.85, 0.85)
		
		var sample_l = int(out_l * 32767.0)
		var sample_r = int(out_r * 32767.0)
		
		var u_l = sample_l if sample_l >= 0 else (65536 + sample_l)
		var u_r = sample_r if sample_r >= 0 else (65536 + sample_r)
		
		var offset = i * 4
		byte_array.encode_u16(offset, u_l)
		byte_array.encode_u16(offset + 2, u_r)
	
	bgm_stream = AudioStreamWAV.new()
	bgm_stream.format = AudioStreamWAV.FORMAT_16_BITS
	bgm_stream.mix_rate = sample_rate
	bgm_stream.stereo = true
	bgm_stream.data = byte_array
	bgm_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bgm_stream.loop_begin = 0
	bgm_stream.loop_end = total_samples

func _generate_sfx_library() -> void:
	sfx_library["click"] = _generate_tone(520.0, 0.04, 0.2)
	sfx_library["success"] = _generate_success_chime()
	sfx_library["error"] = _generate_tone(180.0, 0.15, 0.25)
	sfx_library["redeem"] = _generate_redeem_fanfare()

func _generate_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate: int = 44100
	var total_samples = int(duration * sample_rate)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var env = exp(-t * 25.0)
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
	var sample_rate: int = 44100
	var duration: float = 0.35
	var total_samples = int(duration * sample_rate)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var env = exp(-t * 7.0)
		var freq = 523.25
		if t > 0.09: freq = 659.25
		if t > 0.18: freq = 783.99
		var wave = sin(2.0 * PI * freq * t) * env * 0.28
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
	var sample_rate: int = 44100
	var duration: float = 0.55
	var total_samples = int(duration * sample_rate)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var env = exp(-t * 4.0)
		var freq = 523.25 # C5
		if t > 0.11: freq = 659.25 # E5
		if t > 0.22: freq = 783.99 # G5
		if t > 0.33: freq = 1046.50 # C6
		var wave = (sin(2.0 * PI * freq * t) + 0.3 * sin(2.0 * PI * freq * 2.0 * t)) * env * 0.26
		var sample_int = int(clampf(wave, -1.0, 1.0) * 32767.0)
		var u_sample = sample_int if sample_int >= 0 else (65536 + sample_int)
		byte_array.encode_u16(i * 2, u_sample)
	
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = byte_array
	return wav
