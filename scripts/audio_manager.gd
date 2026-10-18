extends Node

# AudioManager Autoload (res://scripts/audio_manager.gd)
# Features 100% Halal / clean high-fidelity stereo cyber ambient synth soundtrack (44.1 kHz),
# with lush analog pads, melodic arpeggios, warm sub-bass, and procedural SFX.

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

# Generate high-fidelity lush stereo cyber soundtrack (44.1 kHz, 16-bit Stereo)
# Rich ambient pad harmony (Am - F - C - G) with warm sub-bass and crystal bells
func _generate_bgm_track() -> void:
	var sample_rate: int = 44100
	var bpm: float = 110.0
	var beat_duration: float = 60.0 / bpm
	var total_beats: float = 16.0 # 4 bars (4/4 time)
	var duration: float = total_beats * beat_duration
	var total_samples: int = int(duration * sample_rate)
	
	# Musical Tempered Frequencies (A3 = 220Hz, F3 = 174.61Hz, C4 = 261.63Hz, G3 = 196Hz)
	var chords = [
		{"root": 220.00, "third": 261.63, "fifth": 329.63, "bass": 110.00}, # Am
		{"root": 174.61, "third": 220.00, "fifth": 261.63, "bass": 87.31},  # F
		{"root": 261.63, "third": 329.63, "fifth": 392.00, "bass": 130.81}, # C
		{"root": 196.00, "third": 246.94, "fifth": 293.66, "bass": 98.00}   # G
	]
	
	# Arpeggio steps (offsets in semitones: 0, 7, 12, 16, 12, 7, 12, 19)
	var arp_semitones = [0, 7, 12, 16, 12, 7, 12, 19]
	
	# Stereo buffer (Left: int16, Right: int16 -> 4 bytes per sample frame)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 4)
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		var beat_num = t / beat_duration
		var bar_num = int(beat_num / 4.0) % chords.size()
		var chord = chords[bar_num]
		
		# Smooth Bar Envelope (soft attack and gentle crossfade between chords)
		var bar_time = fmod(beat_num, 4.0) / 4.0
		var bar_env = sin(bar_time * PI)
		bar_env = clampf(bar_env * 1.25, 0.0, 1.0)
		
		# 1. Warm Analog Pad (Two detuned oscillators for lush stereo chorus)
		var pad_l = (sin(2.0 * PI * chord["root"] * t) + 0.6 * sin(2.0 * PI * chord["third"] * t) + 0.5 * sin(2.0 * PI * chord["fifth"] * t)) * 0.22
		var pad_r = (sin(2.0 * PI * (chord["root"] + 0.4) * t) + 0.6 * sin(2.0 * PI * (chord["third"] - 0.3) * t) + 0.5 * sin(2.0 * PI * (chord["fifth"] + 0.5) * t)) * 0.22
		
		# 2. Warm Filtered Sub-Bass (Soft, rounded tone)
		var bass = sin(2.0 * PI * chord["bass"] * t) * 0.28
		
		# 3. Crystal Cyber Arpeggio (Soft decaying bell chime on every half-beat)
		var arp_index = int(beat_num * 2.0) % arp_semitones.size()
		var semitone = arp_semitones[arp_index]
		var note_freq = chord["root"] * pow(2.0, float(semitone) / 12.0)
		
		var arp_time = fmod(beat_num * 2.0, 1.0) * (beat_duration * 0.5)
		var arp_env = exp(-arp_time * 6.5) # Natural gentle exponential decay
		# Soft chime with pure fundamental and subtle 2nd harmonic
		var arp_tone = (sin(2.0 * PI * note_freq * t) + 0.25 * sin(2.0 * PI * note_freq * 2.0 * t)) * arp_env * 0.16
		
		# Panning the arpeggio slightly between left and right depending on note
		var pan_factor = 0.5 + 0.3 * sin(float(arp_index) * 1.2)
		var arp_l = arp_tone * pan_factor
		var arp_r = arp_tone * (1.0 - pan_factor)
		
		# Combine channels
		var out_l = (pad_l * bar_env) + (bass * 0.8) + arp_l
		var out_r = (pad_r * bar_env) + (bass * 0.8) + arp_r
		
		# Master smooth soft-limiter
		out_l = clampf(out_l * 0.65, -0.9, 0.9)
		out_r = clampf(out_r * 0.65, -0.9, 0.9)
		
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
