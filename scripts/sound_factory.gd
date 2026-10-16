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
	var b := _buf(0.35)
	var phase := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var u := t / 0.35
		phase += (150.0 - 50.0 * u) / RATE
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
