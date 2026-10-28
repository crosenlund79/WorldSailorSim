"""Generates the TEMPORARY placeholder/test sounds in assets/audio/placeholder.

These are synthetic test signals used to verify audio bus routing and volume
settings. They are not game audio and are meant to be replaced.

Usage: python3 tools/generate_placeholder_audio.py [name.wav ...]
With file names, only those files are written (the others are left as they
are).
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "placeholder")


ONLY = set(sys.argv[1:])


def write(name, samples):
    if ONLY and name not in ONLY:
        return
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))
    print("wrote", path)


def envelope(i, n, attack=0.01, release=0.05):
    t, dur = i / RATE, n / RATE
    return min(1.0, t / attack) * min(1.0, (dur - t) / release)


def tone(freq, dur, amp=0.4, attack=0.01, release=0.05):
    n = int(dur * RATE)
    return [amp * envelope(i, n, attack, release) * math.sin(2 * math.pi * freq * i / RATE) for i in range(n)]


def noise_loop(dur, amp, smooth, swell_hz):
    """Brown-ish noise with a slow swell. Starts and ends near silence-free
    continuity by crossfading the tail into the head so it loops cleanly."""
    random.seed(7)
    n = int(dur * RATE)
    out, v = [], 0.0
    for i in range(n):
        v += (random.uniform(-1, 1) - v) * smooth
        swell = 0.65 + 0.35 * math.sin(2 * math.pi * swell_hz * i / RATE)
        out.append(v * swell)
    peak = max(abs(s) for s in out) or 1.0
    out = [s / peak * amp for s in out]
    fade = int(0.5 * RATE)
    for i in range(fade):
        a = i / fade
        out[i] = out[i] * a + out[n - fade + i] * (1 - a)
    return out[: n - fade]


def engine_loop(dur, amp, cutoff_hz):
    """Diesel-like hum: 55 Hz with harmonics, a 27.5 Hz firing pulse and an
    8 Hz throb. Every component completes whole cycles in `dur` (2 s), so the
    loop is seamless. `cutoff_hz` applies a one-pole low-pass (run over two
    periods so the filter is settled and the loop still joins up), used for
    the muffled version heard below deck."""
    n = int(dur * RATE)
    base = []
    for i in range(n):
        t = i / RATE
        s = (0.55 * math.sin(2 * math.pi * 55 * t)
             + 0.30 * math.sin(2 * math.pi * 110 * t + 0.4)
             + 0.18 * math.sin(2 * math.pi * 165 * t + 1.1)
             + 0.10 * math.sin(2 * math.pi * 220 * t + 2.0)
             + 0.07 * math.sin(2 * math.pi * 330 * t + 0.7))
        pulse = 0.75 + 0.25 * max(0.0, math.sin(2 * math.pi * 27.5 * t)) ** 4
        throb = 0.85 + 0.15 * math.sin(2 * math.pi * 8 * t)
        base.append(s * pulse * throb)
    if cutoff_hz:
        k = 1 - math.exp(-2 * math.pi * cutoff_hz / RATE)
        y, out = 0.0, []
        for rep in range(2):
            out = []
            for s in base:
                y += (s - y) * k
                out.append(y)
        base = out
    peak = max(abs(s) for s in base) or 1.0
    return [s / peak * amp for s in base]


os.makedirs(OUT, exist_ok=True)
# Music bus test: a short, calm arpeggio (D major-ish).
arp = []
for f in (293.66, 369.99, 440.0, 587.33):
    arp += tone(f, 0.35, 0.35, 0.02, 0.2)
write("test_music_arpeggio.wav", arp)
# Ambience bus: soft wash loops for deck and cabin.
write("placeholder_ambience_deck.wav", noise_loop(6.0, 0.35, 0.08, 0.18))
write("placeholder_ambience_cabin.wav", noise_loop(6.0, 0.22, 0.02, 0.1))
# SFX bus test: a short two-tone blip.
write("test_sfx_blip.wav", tone(660, 0.07, 0.4) + tone(880, 0.09, 0.4))
# UI bus: a very short soft click.
write("ui_click.wav", tone(1200, 0.03, 0.25, 0.002, 0.02))
# SFX bus: engine loops (open air on deck, muffled below deck / at the chart).
write("engine_hum.wav", engine_loop(2.0, 0.5, 0))
write("engine_hum_muffled.wav", engine_loop(2.0, 0.5, 140))


def purr(dur, amp):
    """Soft cat purr: low filtered noise pulsing at ~26 Hz, in two breaths."""
    random.seed(11)
    n = int(dur * RATE)
    out, v = [], 0.0
    for i in range(n):
        t = i / RATE
        v += (random.uniform(-1, 1) - v) * 0.04
        pulse = 0.55 + 0.45 * math.sin(2 * math.pi * 26 * t) ** 2
        breath = math.sin(math.pi * ((t % (dur / 2)) / (dur / 2))) ** 0.8
        out.append(v * pulse * breath)
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak * amp * envelope(i, n, 0.05, 0.2) for i, s in enumerate(out)]


def dog_pant(dur, amp):
    """Gentle, happy dog panting: short airy breaths, then a contented sigh."""
    random.seed(23)
    n = int(dur * RATE)
    out, v = [], 0.0
    for i in range(n):
        t = i / RATE
        v += (random.uniform(-1, 1) - v) * 0.25
        if t < dur * 0.65:
            phase = (t * 4.2) % 1.0
            breath = math.sin(math.pi * min(phase / 0.45, 1.0)) if phase < 0.45 else 0.0
            level = 0.8
        else:
            u = (t - dur * 0.65) / (dur * 0.35)
            breath = math.sin(math.pi * u) ** 1.5
            level = 0.55
        out.append(v * breath * level)
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak * amp * envelope(i, n, 0.02, 0.15) for i, s in enumerate(out)]


# SFX bus: ship's companion responses to petting (soft, never harsh test tones).
write("companion_purr.wav", purr(1.6, 0.4))
write("companion_dog_pant.wav", dog_pant(1.6, 0.3))


def parrot_chirp(dur, amp):
    """I024: a small parrot's two soft chirps and a short whistle (a
    green-cheeked conure, not a squawking macaw)."""
    n = int(dur * RATE)
    out = [0.0] * n
    # (start s, length s, from Hz, to Hz, level)
    notes = [(0.02, 0.07, 2900, 3600, 0.8), (0.14, 0.06, 3100, 3800, 0.7), (0.34, 0.22, 2200, 2700, 0.55)]
    for start, length, f0, f1, level in notes:
        i0, m = int(start * RATE), int(length * RATE)
        phase = 0.0
        for k in range(m):
            if i0 + k >= n:
                break
            u = k / m
            f = f0 + (f1 - f0) * math.sin(u * math.pi / 2)
            phase += 2 * math.pi * f / RATE
            env = math.sin(math.pi * u) ** 1.5
            out[i0 + k] += level * env * (math.sin(phase) + 0.18 * math.sin(2 * phase))
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak * amp for s in out]


write("companion_parrot_chirp.wav", parrot_chirp(0.7, 0.28))


def storm_wind(dur, amp):
    """Strong wind in the rigging (Iteration 005a): bright gusting noise with a
    faint whistle, crossfaded to loop. Played louder the stronger the wind."""
    random.seed(31)
    n = int(dur * RATE)
    out, v, w = [], 0.0, 0.0
    for i in range(n):
        t = i / RATE
        v += (random.uniform(-1, 1) - v) * 0.35
        w += (random.uniform(-1, 1) - w) * 0.03
        gust = 0.55 + 0.45 * math.sin(2 * math.pi * 0.23 * t + 1.3 * math.sin(2 * math.pi * 0.07 * t)) ** 2
        whistle = 0.08 * math.sin(2 * math.pi * (620 + 80 * math.sin(2 * math.pi * 0.3 * t)) * t)
        out.append((v * 0.7 + w * 0.6 + whistle) * gust)
    peak = max(abs(s) for s in out) or 1.0
    out = [s / peak * amp for s in out]
    fade = int(0.6 * RATE)
    for i in range(fade):
        a = i / fade
        out[i] = out[i] * a + out[n - fade + i] * (1 - a)
    return out[: n - fade]


def thunder(dur, amp):
    """Distant thunder (Iteration 005a): a soft crack, then a low rolling rumble."""
    random.seed(37)
    n = int(dur * RATE)
    out, v = [], 0.0
    for i in range(n):
        t = i / RATE
        v += (random.uniform(-1, 1) - v) * 0.012
        crack = random.uniform(-1, 1) * math.exp(-t * 18.0) * 0.3
        roll = (0.6 + 0.4 * math.sin(2 * math.pi * 1.7 * t) ** 2) * math.exp(-t * 0.9)
        out.append(v * roll * 9.0 + crack)
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak * amp * envelope(i, n, 0.005, 0.4) for i, s in enumerate(out)]


# Ambience bus: hazardous weather (strong wind loop, occasional thunder).
write("storm_wind.wav", storm_wind(6.0, 0.4))
write("thunder.wav", thunder(3.5, 0.45))


# --- Visual Identity V01: the captain's hat --------------------------------------

def chime(dur, amp):
    """A soft two-note bell (G5 then D6), each with a gentle decay and a quiet
    octave partial: a pleasant "found something" cue, never loud."""
    n = int(dur * RATE)
    out = [0.0] * n
    for start, freq in ((0.0, 784.0), (0.16, 1174.7)):
        s0 = int(start * RATE)
        for i in range(s0, n):
            t = (i - s0) / RATE
            env = min(1.0, t / 0.006) * math.exp(-t * 4.2)
            out[i] += amp * env * (math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(2 * math.pi * freq * 2 * t))
    fade = int(0.05 * RATE)
    for i in range(fade):
        out[n - 1 - i] *= i / fade
    return out


def sour_note(dur, amp):
    """A playful "wah-wah": two muted, slightly flat notes sliding down, with a
    little vibrato and a soft reedy tone. Comic, short and quiet."""
    n = int(dur * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        first = t < dur * 0.45
        local = t if first else t - dur * 0.45
        span = dur * 0.45 if first else dur * 0.55
        f0, f1 = (392.0, 349.0) if first else (330.0, 262.0)
        freq = f0 + (f1 - f0) * min(1.0, local / span) + 4.0 * math.sin(2 * math.pi * 6.0 * t)
        phase += 2 * math.pi * freq / RATE
        env = min(1.0, local / 0.03) * min(1.0, (span - local) / 0.08)
        tone_ = math.sin(phase) + 0.35 * math.sin(2 * phase) + 0.12 * math.sin(3 * phase)
        out.append(amp * env * tone_ / 1.47)
    return out


write("achievement_chime.wav", chime(1.1, 0.22))
write("hat_sour_note.wav", sour_note(0.9, 0.24))


# --- Iteration 13: fishing, the galley and the anchor ------------------------------
# Small, quiet cues. Every one of them has a visible counterpart in the game
# (a toast, a badge or a panel), so nothing depends on hearing it.

def filtered_noise(n, smooth, seed):
    random.seed(seed)
    out, v = [], 0.0
    for _ in range(n):
        v += (random.uniform(-1, 1) - v) * smooth
        out.append(v)
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak for s in out]


def cast(dur, amp):
    """A rod's swish, then the line running out with a faint reel buzz."""
    n = int(dur * RATE)
    air = filtered_noise(n, 0.3, 41)
    out = []
    for i in range(n):
        t = i / RATE
        swish = math.exp(-((t - 0.12) / 0.07) ** 2)
        buzz = 0.25 * math.sin(2 * math.pi * 38 * t) ** 8 * math.exp(-max(t - 0.2, 0) * 3.0) if t > 0.2 else 0.0
        out.append(amp * (air[i] * swish + buzz * air[i]))
    return out


def bite(dur, amp):
    """A little bell on the rod tip: two quick taps."""
    n = int(dur * RATE)
    out = [0.0] * n
    for start in (0.0, 0.18):
        s0 = int(start * RATE)
        for i in range(s0, n):
            t = (i - s0) / RATE
            out[i] += amp * min(1.0, t / 0.003) * math.exp(-t * 9.0) * (math.sin(2 * math.pi * 1760 * t) + 0.4 * math.sin(2 * math.pi * 2640 * t))
    return out


def reel(dur, amp):
    """A reel's soft ratchet clicks."""
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        phase = (t * 22.0) % 1.0
        click = math.exp(-phase * 60.0) * math.sin(2 * math.pi * 2200 * t)
        out.append(amp * click * envelope(i, n, 0.02, 0.1))
    return out


def splash(dur, amp):
    """The fish coming aboard: a short wet splash and a flap on the deck."""
    n = int(dur * RATE)
    water = filtered_noise(n, 0.5, 43)
    out = []
    for i in range(n):
        t = i / RATE
        s = water[i] * math.exp(-t * 7.0)
        if 0.35 < t < 0.42:
            s += 0.6 * water[i] * math.sin(math.pi * (t - 0.35) / 0.07)
        out.append(amp * s * envelope(i, n, 0.004, 0.1))
    return out


def snap(dur, amp):
    """The line parting: a light twang falling away."""
    n = int(dur * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (520 - 260 * t / dur) / RATE
        out.append(amp * min(1.0, t / 0.002) * math.exp(-t * 6.0) * math.sin(phase))
    return out


def sizzle(dur, amp):
    """A pan sizzling softly, with a little bubble of a pot now and then."""
    n = int(dur * RATE)
    hiss = filtered_noise(n, 0.85, 47)
    random.seed(53)
    out = []
    for i in range(n):
        t = i / RATE
        crackle = 1.0 if random.random() < 0.004 else 0.0
        level = 0.5 + 0.2 * math.sin(2 * math.pi * 0.8 * t)
        out.append(amp * (hiss[i] * level * 0.6 + crackle * 0.5) * envelope(i, n, 0.15, 0.4))
    return out


def chain(dur, amp):
    """Anchor chain running out over the bow roller: a rattle that slows."""
    n = int(dur * RATE)
    out = [0.0] * n
    t, rate = 0.0, 18.0
    random.seed(59)
    while t < dur - 0.05:
        s0 = int(t * RATE)
        freq = random.uniform(900, 1500)
        for i in range(s0, min(n, s0 + int(0.04 * RATE))):
            u = (i - s0) / RATE
            out[i] += amp * math.exp(-u * 90.0) * math.sin(2 * math.pi * freq * u) * random.uniform(0.6, 1.0)
        t += 1.0 / rate
        rate = max(rate * 0.985, 7.0)
    out[-int(0.2 * RATE):] = [s * (1 - k / int(0.2 * RATE)) for k, s in enumerate(out[-int(0.2 * RATE):])]
    return out


def warning(dur, amp):
    """A soft, unmistakable double beep (anchor alarm, fishing warnings)."""
    out = []
    for _ in range(2):
        out += tone(988.0, 0.14, amp, 0.005, 0.04) + [0.0] * int(0.08 * RATE)
    return out + tone(784.0, 0.22, amp, 0.005, 0.08)


write("fishing_cast.wav", cast(0.9, 0.3))
write("fishing_bite.wav", bite(0.6, 0.18))
write("fishing_reel.wav", reel(0.7, 0.18))
write("fishing_splash.wav", splash(0.7, 0.32))
write("fishing_snap.wav", snap(0.5, 0.25))
write("galley_sizzle.wav", sizzle(2.0, 0.25))
write("anchor_chain.wav", chain(1.6, 0.25))
write("warning_beep.wav", warning(0.8, 0.2))
