extends RefCounted
## Synthesises every sound effect in code (noise bursts, filtered noise and
## a few sine partials), so the game ships with no audio files. Each function
## returns an AudioStreamWAV. Replace any of them with a recorded .wav later
## by loading it into the same Dictionary key.

const RATE := 22050


## Built once per run: synthesising every sound takes a while on a phone,
## and they never change.
static var _cache: Dictionary = {}


static func is_cached() -> bool:
	return not _cache.is_empty()


static func cached() -> Dictionary:
	if _cache.is_empty():
		_cache = build_all()
	return _cache


static func build_all() -> Dictionary:
	return {
		"musket": musket(),
		"ramrod": ramrod(),
		"stab": stab(),
		"clang": clang(),
		"swish": swish(),
		"hiss": hiss(),
		"roar": roar(),
		"death": death_roar(),
		"grunt": grunt(),
		"bayonet": bayonet_fix(),
		"boom": boom(),
		"thud": thud(),
		"cannon": cannon(),
		"thunder": thunder(),
		"storm": storm(),
		"surf": surf(),
		"crack": crack(),
		"bow": bow(),
		"crossbow": crossbow(),
		"crank": crank(),
		"drum": drum(),
		"shout": shout(),
		"plop": plop(),
		"splash": splash(),
		"reel": reel(),
		"talk1": talk(1, 1.5, 118.0),
		"talk2": talk(2, 1.7, 132.0),
		"talk3": talk(3, 1.3, 104.0),
		"talk4": talk(4, 1.8, 150.0),
	}


# ---------------------------------------------------------------- helpers

static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := clampi(int(samples[i] * gain * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _noise() -> float:
	return randf() * 2.0 - 1.0


# ---------------------------------------------------------------- sounds

## A flintlock: sharp crack, then a heavy low boom with a rolling tail.
static func musket() -> AudioStreamWAV:
	var b := _buf(1.4)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise()
		var crack := n * exp(-t / 0.018)
		lp += 0.08 * (n - lp)
		lp2 += 0.05 * (lp - lp2)
		var boom := lp2 * 6.0 * exp(-t / 0.35)
		var thump := sin(TAU * (55.0 - 20.0 * t) * t) * exp(-t / 0.12) * 0.8
		b[i] = crack * 0.9 + boom + thump
	return _to_wav(b)


## A grenade: a sharp crack, a deep blast and a long rumbling tail.
static func boom() -> AudioStreamWAV:
	var b := _buf(2.2)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise()
		lp += 0.05 * (n - lp)
		lp2 += 0.03 * (lp - lp2)
		var crack := n * exp(-t / 0.03)
		var blast := lp2 * 9.0 * exp(-t / 0.6)
		var thump := sin(TAU * (42.0 - 15.0 * t) * t) * exp(-t / 0.25)
		b[i] = crack * 0.8 + blast + thump
	return _to_wav(b)


## A field gun: a deep, long boom with a hard crack on top.
static func cannon() -> AudioStreamWAV:
	var b := _buf(2.8)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise()
		lp += 0.04 * (n - lp)
		lp2 += 0.02 * (lp - lp2)
		var crack := n * exp(-t / 0.02)
		var blast := lp2 * 12.0 * exp(-t / 0.8)
		var thump := sin(TAU * (34.0 - 10.0 * t) * t) * exp(-t / 0.35)
		b[i] = crack * 0.6 + blast + thump * 1.2
	return _to_wav(b)


## Thunder: a crack, then a long rolling rumble that swells and fades.
static func thunder() -> AudioStreamWAV:
	var b := _buf(4.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise()
		lp += 0.03 * (n - lp)
		lp2 += 0.015 * (lp - lp2)
		var roll := lp2 * 14.0 * (0.6 + 0.4 * sin(t * 7.0) * sin(t * 2.3)) * exp(-t / 1.4)
		b[i] = n * exp(-t / 0.05) * 0.5 + roll
	return _to_wav(b)


## Wind and rain: a loopable roar of filtered noise.
static func storm() -> AudioStreamWAV:
	var b := _buf(4.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise()
		lp += 0.06 * (n - lp)
		lp2 += 0.3 * (n - lp2)
		var gust := 0.6 + 0.4 * sin(TAU * t / 4.0) # one full gust per loop
		b[i] = lp * 3.0 * gust + (n - lp2) * 0.25
	var w := _to_wav(b)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = b.size()
	return w


## Waves on a beach: slow swells of soft noise. Loops.
static func surf() -> AudioStreamWAV:
	var b := _buf(6.0)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.08 * (_noise() - lp)
		var swell := pow(0.5 + 0.5 * sin(TAU * t / 3.0 - 1.5), 2.0)
		b[i] = lp * (0.2 + swell)
	var w := _to_wav(b)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = b.size()
	return w


## Timber splitting: a run of sharp cracks over a groan.
static func crack() -> AudioStreamWAV:
	var b := _buf(1.6)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += (70.0 + 30.0 * sin(t * 9.0)) / RATE
		var groan := (2.0 * (phase - floorf(phase)) - 1.0) * 0.3 * exp(-t / 0.8)
		var snaps := 0.0
		for k in 5:
			var ct := t - k * 0.13
			if ct > 0.0:
				snaps += _noise() * exp(-ct / 0.012)
		b[i] = groan + snaps
	return _to_wav(b)


## Something heavy landing on turf.
static func thud() -> AudioStreamWAV:
	var b := _buf(0.18)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.1 * (_noise() - lp)
		b[i] = lp * exp(-t / 0.03) + sin(TAU * 90.0 * t) * exp(-t / 0.04) * 0.5
	return _to_wav(b)


## A float or a small fish going into water: a short falling "plop".
static func plop() -> AudioStreamWAV:
	var b := _buf(0.22)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.25 * (_noise() - lp)
		var f := 900.0 * exp(-t / 0.05) + 260.0
		b[i] = sin(TAU * f * t) * exp(-t / 0.05) * 0.8 + lp * exp(-t / 0.02) * 0.6
	return _to_wav(b)


## A fish thrashing at the surface: a burst of wet, broken noise.
static func splash() -> AudioStreamWAV:
	var b := _buf(0.6)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise()
		lp += 0.35 * (n - lp)
		lp2 += 0.05 * (lp - lp2)
		var grain := 0.5 + 0.5 * sin(TAU * 23.0 * t + sin(TAU * 7.0 * t) * 3.0)
		b[i] = (lp - lp2) * grain * exp(-t / 0.22)
	return _to_wav(b)


## The reel's click: a few quick ticks of a wooden ratchet.
static func reel() -> AudioStreamWAV:
	var b := _buf(0.3)
	for i in b.size():
		var t := float(i) / RATE
		var ph := fmod(t * 26.0, 1.0)
		b[i] = _noise() * exp(-ph / 0.06) * 0.7 + sin(TAU * 2400.0 * t) * exp(-ph / 0.02) * 0.3
	return _to_wav(b)


## A big skin drum far off in the trees: a deep, soft boom.
static func drum() -> AudioStreamWAV:
	var b := _buf(1.2)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.04 * (_noise() - lp)
		var body := sin(TAU * (62.0 + 30.0 * exp(-t / 0.05)) * t) * exp(-t / 0.35)
		b[i] = body + lp * 4.0 * exp(-t / 0.08)
	return _to_wav(b)


## A shouted order or a cry: a quick hard run of voice blips (the gravel
## voice of talk(), louder, faster, higher), like a word or two barked out.
## (It used to be a long sung "HAA-ah" through formants, which came out as a
## moan.)
static func shout() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var b := _buf(0.42)
	var t0 := 0.01
	var k := 0
	while t0 < 0.34:
		_blip(b, int(t0 * RATE), 2, 400.0 * (1.06 if k == 0 else rng.randf_range(0.95, 1.02)), rng)
		t0 += 0.062 if k != 1 else 0.11 # (a beat between the words)
		k += 1
	return _to_wav(b)


## Someone talking, the way Robot Fighting's characters talk: a run of
## short voice blips (saw + square through a soft low-pass, about 60 ms
## each, 13 a second) with little gaps between words and the pitch
## wandering a little and falling toward the end of the sentence. No words:
## the captions carry them. `seed_n` picks the voice:
##   1 clean (most men), 2 gravel (a growl in it: sergeants, old soldiers),
##   3 smooth (round, warm: officers), 4 nasal (thin, reedy).
## Pitched where phone speakers can play them (300 to 400 Hz); play them at
## other pitches for other men (battle.speak, town, the cutscenes).
static func talk(seed_n: int, seconds: float, base: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed_n
	var b := _buf(seconds)
	var f0: float = [360.0, 330.0, 300.0, 380.0][(seed_n - 1) % 4]
	var t0 := 0.02
	var in_word := 0
	var word_len := rng.randi_range(2, 5)
	while t0 < seconds - 0.08:
		var lift := rng.randf_range(0.93, 1.08) * lerpf(1.06, 0.9, t0 / seconds)
		_blip(b, int(t0 * RATE), seed_n, f0 * lift, rng)
		in_word += 1
		t0 += rng.randf_range(0.068, 0.084)
		if in_word >= word_len:
			in_word = 0
			word_len = rng.randi_range(2, 5)
			t0 += rng.randf_range(0.07, 0.14) # (between words)
	return _to_wav(b)


## One voice blip into `b` at sample `at`: a short sweep down from `f` with
## a quick attack and a fast decay.
static func _blip(b: PackedFloat32Array, at: int, kind: int, f: float, rng: RandomNumberGenerator) -> void:
	var dur := 0.058 if kind != 3 else 0.062
	var n := int(dur * RATE)
	var ph := 0.0
	var lp := 0.0
	var lpn := 0.0
	var growl := 1.0
	for i in n:
		var j := at + i
		if j >= b.size():
			break
		var t := float(i) / RATE
		var fr := lerpf(f, f * 0.88, t / dur)
		ph += fr / RATE
		ph -= floorf(ph)
		var saw := ph * 2.0 - 1.0
		var sq := 0.7 if ph < 0.5 else -0.7
		var y := 0.0
		match kind:
			2: # gravel: a growl that stutters, and breath
				if i % int(RATE * 0.0075) == 0:
					growl = rng.randf_range(0.4, 1.0)
				lp += 0.8 * (saw - lp)
				lpn += 0.4 * (_noise() - lpn)
				y = (lp + sq * 0.3) * growl + lpn * 0.25
			3: # smooth: a round tone and its octave
				y = sin(ph * TAU) + sin(ph * TAU * 2.0) * 0.25
			4: # nasal: a thin, filtered saw
				lp += 0.5 * (saw - lp)
				y = lp * 1.4
			_: # clean
				lp += 0.7 * (saw - lp)
				y = lp + sq * 0.25
		var env := minf(1.0, t / 0.005) * exp(-t / 0.04)
		var rel := clampf((dur - t) / 0.01, 0.0, 1.0)
		b[j] += y * env * rel


## A bowstring let go: a low twang that dies fast, and the hiss of the shaft.
static func bow() -> AudioStreamWAV:
	var b := _buf(0.45)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 110.0 + 40.0 * exp(-t / 0.02)
		var twang := (sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.01 * t) + 0.25 * sin(TAU * f * 3.03 * t)) * exp(-t / 0.07)
		lp += 0.3 * (_noise() - lp)
		var hiss := (_noise() - lp) * exp(-pow((t - 0.05) / 0.04, 2.0)) * 0.35
		b[i] = twang + hiss + _noise() * exp(-t / 0.003) * 0.5
	return _to_wav(b)


## A crossbow's release: the hard snap of the steel prod and a wooden thunk.
static func crossbow() -> AudioStreamWAV:
	var b := _buf(0.4)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.12 * (_noise() - lp)
		var snap := _noise() * exp(-t / 0.004)
		var thunk := sin(TAU * (180.0 - 150.0 * t) * t) * exp(-t / 0.05)
		var ring := sin(TAU * 640.0 * t) * exp(-t / 0.09) * 0.3
		b[i] = snap * 0.9 + thunk + lp * exp(-t / 0.03) * 2.0 + ring
	return _to_wav(b)


## A windlass winding a crossbow back: a run of ratchet clicks.
static func crank() -> AudioStreamWAV:
	var b := _buf(0.5)
	for i in b.size():
		var t := float(i) / RATE
		var ph := fmod(t, 0.07)
		b[i] = (_noise() * 0.6 + sin(TAU * 2900.0 * t) * 0.4) * exp(-ph / 0.006)
	return _to_wav(b)


## Iron ramrod clinking in the barrel.
static func ramrod() -> AudioStreamWAV:
	var b := _buf(0.3)
	for i in b.size():
		var t := float(i) / RATE
		var env := exp(-t / 0.04)
		var s := sin(TAU * 2150.0 * t) + 0.6 * sin(TAU * 3240.0 * t) + 0.4 * sin(TAU * 4620.0 * t)
		b[i] = s * env * 0.5 + _noise() * exp(-t / 0.006) * 0.4
	return _to_wav(b)


## Bayonet or cleaver going in: a dull, wet thud.
static func stab() -> AudioStreamWAV:
	var b := _buf(0.35)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.15 * (_noise() - lp)
		var body := sin(TAU * (160.0 - 200.0 * t) * t) * exp(-t / 0.07)
		b[i] = lp * 3.0 * exp(-t / 0.05) + body * 0.8
	return _to_wav(b)


## Steel on steel (a parry): bright inharmonic ring.
static func clang() -> AudioStreamWAV:
	var b := _buf(0.9)
	var partials := [[820.0, 1.0], [1253.0, 0.7], [1987.0, 0.5], [2711.0, 0.35], [3540.0, 0.2]]
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		for p in partials:
			s += sin(TAU * float(p[0]) * t) * float(p[1]) * exp(-t / (0.32 / (1.0 + float(p[0]) / 2000.0)))
		b[i] = s + _noise() * exp(-t / 0.01) * 0.8
	return _to_wav(b)


## A blade cutting air: band-limited noise that swells and fades.
static func swish() -> AudioStreamWAV:
	var b := _buf(0.28)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / b.size()
		var n := _noise()
		var a := 0.1 + 0.5 * t # filter opens as the blade speeds up
		lp += a * (n - lp)
		lp2 += 0.04 * (lp - lp2)
		b[i] = (lp - lp2) * sin(PI * t)
	return _to_wav(b)


## Reptile hiss: high, airy noise.
static func hiss() -> AudioStreamWAV:
	var b := _buf(0.5)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / b.size()
		var n := _noise()
		lp += 0.3 * (n - lp)
		var hp := n - lp
		var env := sin(PI * minf(t * 3.0, 1.0) * 0.5) * (1.0 - t)
		b[i] = hp * env
	return _to_wav(b)


## Lizardman war cry: a growling, wobbling low saw wave with noise.
static func roar() -> AudioStreamWAV:
	return _growl(1.1, 120.0, -30.0)


static func death_roar() -> AudioStreamWAV:
	return _growl(0.9, 150.0, -110.0)


static func _growl(seconds: float, f0: float, slide: float) -> AudioStreamWAV:
	var b := _buf(seconds)
	var phase := 0.0
	var lp := 0.0
	var lpn := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var u := t / seconds
		var f := f0 + slide * u + 9.0 * sin(TAU * 7.0 * t)
		phase += f / RATE
		var saw := 2.0 * (phase - floorf(phase)) - 1.0
		var n := _noise()
		lpn += 0.2 * (n - lpn)
		var raw := saw * (0.8 + 0.4 * lpn) + lpn * 0.5
		lp += 0.18 * (raw - lp)
		var env := minf(u * 8.0, 1.0) * (1.0 - u) * (1.0 - u)
		b[i] = lp * env
	return _to_wav(b)


## A man taking a hit.
static func grunt() -> AudioStreamWAV:
	# (short and dry: a long falling one came out as a moan)
	var b := _buf(0.16)
	var phase := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var u := t / 0.16
		phase += (200.0 - 30.0 * u) / RATE
		var saw := 2.0 * (phase - floorf(phase)) - 1.0
		lp += 0.12 * (saw - lp)
		b[i] = lp * sin(PI * minf(u * 2.5, 1.0)) * (1.0 - u)
	return _to_wav(b)


## Bayonet sliding onto the muzzle and locking: a scrape, then a click.
static func bayonet_fix() -> AudioStreamWAV:
	var b := _buf(0.45)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise()
		lp += 0.5 * (n - lp)
		var scrape := (n - lp) * 0.5 * (1.0 if t < 0.28 else 0.0) * sin(PI * minf(t / 0.28, 1.0))
		var ct := t - 0.32
		var click := 0.0
		if ct > 0.0:
			click = (sin(TAU * 2600.0 * ct) + 0.5 * sin(TAU * 4100.0 * ct)) * exp(-ct / 0.025)
		b[i] = scrape + click
	return _to_wav(b)
