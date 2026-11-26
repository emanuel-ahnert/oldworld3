"""Synthesizes the game's sound effects and music.

    python3 tools/audio/makeaudio.py [OUT_DIR] [NAME,NAME...]

Default output: assets/generated/audio, with sounds/NAME.wav and music/NAME.ogg (encoded with
ffmpeg). Needs numpy. Everything is made from oscillators, noise, envelopes, FFT filters and
a convolution reverb; the music comes from a small composer (modes, chord progressions,
melodies from motifs) played by a plucked lute or harp, a flute, a pad, bass and drums. Every
piece is made from a fixed seed, so a rebuild gives the same audio.
"""

import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else ROOT / "assets/generated/audio"
only = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else None

SR = 44100


# ---- building blocks ----

def t_of(dur):
    return np.arange(int(dur * SR)) / SR


def phase(freq, n):
    """The running phase of a (possibly changing) frequency: freq is a number or an array."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return 2 * np.pi * np.cumsum(f) / SR


def osc(kind, freq, dur, duty=0.5):
    n = int(dur * SR)
    ph = phase(freq, n)
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "square":
        return np.where((ph / (2 * np.pi)) % 1 < duty, 1.0, -1.0)
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    raise ValueError(kind)


def noise(dur, rng):
    return rng.uniform(-1, 1, int(dur * SR))


def env(n, a=0.005, d=0.1, s=0.0, r=0.05, hold=None):
    """ADSR over n samples; hold is when the release starts (default: the end minus r)."""
    t = np.arange(n) / SR
    total = n / SR
    hold = total - r if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-6), 1.0)
    dec = np.clip((t - a) / max(d, 1e-6), 0, 1)
    e = np.where(t >= a, 1 - (1 - s) * dec, e)
    rel = np.clip((t - hold) / max(r, 1e-6), 0, 1)
    return e * (1 - rel)


def decay(n, tau):
    return np.exp(-np.arange(n) / SR / tau)


def fft_filter(x, low=None, high=None, order=2):
    """Zero-phase filtering in the frequency domain: low/high are the cutoffs of a low-pass and
    a high-pass (Butterworth-shaped magnitudes)."""
    n = len(x)
    if n == 0:
        return x
    size = 1 << (n - 1).bit_length()
    spec = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1 / SR)
    g = np.ones_like(f)
    if low:
        g /= np.sqrt(1 + (f / low) ** (2 * order))
    if high:
        g *= 1 - 1 / np.sqrt(1 + (f / high) ** (2 * order))
    return np.fft.irfft(spec * g, size)[:n]


def sweep_filter(x, lows, block=1024):
    """A low-pass whose cutoff moves: lows gives the cutoff at the start of each block; blocks
    overlap and crossfade."""
    out = np.zeros(len(x) + block)
    win = np.hanning(2 * block)
    for i, start in enumerate(range(0, len(x), block)):
        seg = x[max(0, start - block // 2):start + block + block // 2]
        f = fft_filter(seg, low=lows[min(i, len(lows) - 1)])
        w = np.hanning(len(f))
        a = max(0, start - block // 2)
        out[a:a + len(f)] += f * w
    return out[:len(x)] / 1.0


def reverb(x, size=1.2, mix=0.25, seed=1, damp=4000, wrap=False):
    """Convolution with decaying, darkened noise: a room or a hall. With wrap, the tail wraps
    around to the start, so a looping track has no gap."""
    rng = np.random.default_rng(seed)
    n = int(size * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR / (size / 5))
    ir = fft_filter(ir, low=damp)
    ir /= np.sqrt(np.sum(ir ** 2))
    m = len(x) + n
    size2 = 1 << (m - 1).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, size2) * np.fft.rfft(ir, size2), size2)[:m]
    if wrap:
        tail = wet[len(x):]
        wet = wet[:len(x)].copy()
        wet[:len(tail)] += tail[:len(x)]
    else:
        x = np.concatenate([x, np.zeros(n)])
    return x * (1 - mix) + wet * mix * 0.6


def mix(*parts):
    """Parts (start in seconds, samples) added into one buffer long enough for all of them."""
    n = max(int(at * SR) + len(p) for at, p in parts)
    out = np.zeros(n)
    for at, p in parts:
        a = int(at * SR)
        out[a:a + len(p)] += p[:max(0, n - a)]
    return out


def place(buf, at, part, gain=1.0):
    a = int(at * SR)
    if a >= len(buf):
        return
    m = min(len(part), len(buf) - a)
    buf[a:a + m] += part[:m] * gain


def normalize(x, peak=0.89):
    m = np.max(np.abs(x))
    return x if m == 0 else x * (peak / m)


def write_wav(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def hz(note):
    """MIDI note number to frequency."""
    return 440.0 * 2 ** ((note - 69) / 12)


# ---- instruments ----

def pluck(freq, dur, bright=1.0, tau=0.6):
    """A plucked string (lute, harp, oud): harmonics that die away, the high ones faster."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 10):
        if freq * k > SR / 2.2:
            break
        amp = (1 / k) * (bright ** (k - 1))
        out += amp * np.sin(2 * np.pi * freq * k * t + k) * np.exp(-t / (tau / (1 + 0.5 * (k - 1))))
    att = np.clip(t / 0.003, 0, 1)
    return out * att * 0.5


def flute(freq, dur, rng, vib=5.0, breath=0.06):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (1 + 0.004 * np.sin(2 * np.pi * vib * t) * np.clip(t / 0.25, 0, 1))
    ph = phase(f, n)
    tone = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    air = fft_filter(rng.uniform(-1, 1, n), low=freq * 3, high=freq) * breath * 6
    e = env(n, a=0.06, d=0.1, s=0.85, r=min(0.12, dur * 0.4))
    return (tone + air) * e * 0.35


def pad(freqs, dur, rng, bright=1800):
    """Soft strings: detuned saws, filtered dark, slow in and out."""
    n = int(dur * SR)
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.004, 0.0, 0.005):
            out += osc("saw", f * (1 + det), dur)
    out = fft_filter(out, low=bright)
    return out * env(n, a=min(0.4, dur * 0.3), d=0.2, s=0.9, r=min(0.5, dur * 0.3)) * 0.08


def bass(freq, dur, kind="tri"):
    n = int(dur * SR)
    x = osc(kind, freq, dur) + 0.3 * osc("sine", freq / 2, dur)
    if kind != "tri":
        x = fft_filter(x, low=freq * 4)
    return x * env(n, a=0.005, d=0.15, s=0.7, r=0.05) * 0.4


def brass(freq, dur):
    n = int(dur * SR)
    x = osc("saw", freq, dur) + 0.5 * osc("saw", freq * 1.003, dur)
    lows = np.linspace(freq * 2, freq * 8, max(1, n // 1024))[: n // 1024 + 1]
    x = sweep_filter(x, lows)
    return x * env(n, a=0.03, d=0.2, s=0.75, r=0.06) * 0.25


def bell(freq, dur, tau=1.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp in ((1, 1), (2.76, 0.5), (5.4, 0.25), (8.9, 0.12)):
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / (tau / ratio ** 0.5))
    return out * np.clip(t / 0.002, 0, 1) * 0.3


def kick(rng, dur=0.35):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t / 0.04)
    return np.sin(phase(f, n)) * np.exp(-t / 0.12) * 0.9


def snare(rng, dur=0.25):
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = fft_filter(rng.uniform(-1, 1, n), low=7000, high=1200) * np.exp(-t / 0.06)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05)
    return (nz * 1.4 + tone * 0.5) * 0.5


def hat(rng, dur=0.06):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return fft_filter(rng.uniform(-1, 1, n), high=7000) * np.exp(-t / 0.015) * 0.35


def frame_drum(rng, low=True, dur=0.4):
    """A hand drum: a deep "dum" or a sharp "tek"."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    if low:
        f = 85 + 40 * np.exp(-t / 0.03)
        return (np.sin(phase(f, n)) * np.exp(-t / 0.15) + fft_filter(rng.uniform(-1, 1, n), low=900) * np.exp(-t / 0.02) * 0.4) * 0.8
    return (fft_filter(rng.uniform(-1, 1, n), low=6000, high=1500) * np.exp(-t / 0.03)
            + np.sin(2 * np.pi * 420 * t) * np.exp(-t / 0.04) * 0.3) * 0.45


def timpani(freq, rng, dur=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = sum(a * np.sin(2 * np.pi * freq * r * t) for r, a in ((1, 1), (1.5, 0.4), (1.99, 0.25)))
    out = out * np.exp(-t / 0.45) + fft_filter(rng.uniform(-1, 1, n), low=600) * np.exp(-t / 0.03) * 0.5
    return out * 0.5


def tambourine(rng, dur=0.18):
    n = int(dur * SR)
    t = np.arange(n) / SR
    jingle = fft_filter(rng.uniform(-1, 1, n), high=6000) * (np.exp(-t / 0.05)) * (1 + 0.5 * np.sin(2 * np.pi * 30 * t))
    return jingle * 0.25


# ---- the composer ----

MODES = {
    "major": [0, 2, 4, 5, 7, 9, 11],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "minor": [0, 2, 3, 5, 7, 8, 10],
    "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "hijaz": [0, 1, 4, 5, 7, 8, 10],  # phrygian dominant
}


class Song:
    def __init__(self, root, mode, bpm, beats=4, seed=1):
        self.root, self.scale, self.bpm, self.beats = root, MODES[mode], bpm, beats
        self.beat = 60 / bpm
        self.rng = np.random.default_rng(seed)

    def note(self, degree, octave=0):
        """A scale degree (0-based, may run past 7) to a MIDI note."""
        o, d = divmod(degree, 7)
        return self.root + 12 * (octave + o) + self.scale[d]

    def chord(self, degree, octave=0):
        return [self.note(degree + i, octave) for i in (0, 2, 4)]

    def melody(self, progression, rhythm_bank, octave=1, start=4):
        """A melody over a progression: one rhythm per bar from the bank, chord tones on the
        strong beats, steps between; phrases repeat with variation (AABA')."""
        rng = self.rng
        phrases = {}
        notes = []  # (start beat, length in beats, degree)
        deg = start
        bar_len = self.beats
        for bar, chord in enumerate(progression):
            phrase = bar // 4 % 4
            key = ("A" if phrase in (0, 1, 3) else "B", bar % 4)
            if key in phrases and not (phrase == 3 and bar % 4 == 3):
                rhythm, shape = phrases[key]
            else:
                rhythm = rhythm_bank[rng.integers(len(rhythm_bank))]
                shape = None
            t = 0.0
            made = []
            for i, length in enumerate(rhythm):
                if shape is not None:
                    d = chord + shape[i] if i < len(shape) else deg
                else:
                    strong = t % 2 == 0
                    tones = [chord, chord + 2, chord + 4, chord + 7]
                    if strong:
                        d = min(tones, key=lambda c: abs(c - deg) + rng.uniform(0, 1.5))
                    else:
                        d = deg + rng.choice([-1, 1, 1, -2, 2])
                    d = int(np.clip(d, 0, 11))
                made.append(d - chord)
                if length > 0:
                    notes.append((bar * bar_len + t, length, d))
                deg = d
                t += abs(length)
            if key not in phrases:
                phrases[key] = (rhythm, made)
        return notes

    def render_notes(self, buf, notes, instrument, octave=1, gain=1.0, legato=1.0):
        for start, length, deg in notes:
            f = hz(self.note(deg, octave))
            dur = length * self.beat * legato
            place(buf, start * self.beat, instrument(f, dur + 0.05), gain)


def finish_track(name, buf, room=1.6, mix_=0.28):
    buf = reverb(buf, size=room, mix=mix_, wrap=True)
    buf = normalize(fft_filter(buf, high=35), 0.8)
    path = out_dir / "music" / f"{name}.ogg"
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "t.wav"
        write_wav(wav, buf)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4", "-ar", "32000",
                        str(path)], check=True)
    print("wrote", path)


# Rhythms in beats; a negative length is a rest.
FLOWING = [[1, 1, 1, 1], [2, 1, 1], [1.5, 0.5, 2], [1, 0.5, 0.5, 2], [3, 1], [0.5, 0.5, 1, 2]]
WALTZ = [[1, 1, 1], [2, 1], [1.5, 0.5, 1], [3]]
DRIVING = [[0.5, 0.5, 0.5, 0.5, 1, 1], [1, 0.5, 0.5, 2], [0.5, 0.5, 1, 0.5, 0.5, 1], [2, 0.5, 0.5, 1]]
SLOW = [[2, 2], [3, 1], [4], [1, 1, 2]]


def song_buffer(s, bars):
    return np.zeros(int(bars * s.beats * s.beat * SR) + 1)


def arpeggio(s, buf, prog, octave, gain, pattern=(0, 1, 2, 1), step=0.5, inst=None):
    inst = inst or (lambda f, d: pluck(f, d, 0.75, 0.7))
    for bar, deg in enumerate(prog):
        ch = s.chord(deg, octave)
        for i in range(int(s.beats / step)):
            place(buf, (bar * s.beats + i * step) * s.beat, inst(hz(ch[pattern[i % len(pattern)]]), step * s.beat * 2.5), gain)


def bassline(s, buf, prog, octave=-1, gain=1.0, kind="tri", pattern=(0, 2)):
    for bar, deg in enumerate(prog):
        for beat in pattern:
            place(buf, (bar * s.beats + beat) * s.beat, bass(hz(s.note(deg, octave)), s.beat * 1.8, kind), gain)


def pads(s, buf, prog, octave=0, gain=1.0, bright=1800):
    for bar, deg in enumerate(prog):
        place(buf, bar * s.beats * s.beat, pad([hz(n) for n in s.chord(deg, octave)], s.beats * s.beat + 0.3, s.rng, bright), gain)


def drums(s, buf, bars, pattern, gain=1.0):
    """pattern: list of (beat, instrument function) per bar."""
    for bar in range(bars):
        for beat, inst in pattern:
            place(buf, (bar * s.beats + beat) * s.beat, inst(), gain)


def track_title():
    s = Song(62, "dorian", 92, seed=11)  # D dorian: hopeful, a little wistful
    prog = [0, 6, 3, 4] * 2 + [5, 3, 0, 4] + [0, 6, 3, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, FLOWING, start=4)
    s.render_notes(buf, mel, lambda f, d: flute(f, d, s.rng), octave=1, gain=1.0)
    arpeggio(s, buf, prog, 0, 0.8, pattern=(0, 1, 2, 1, 2, 1), step=0.5, inst=lambda f, d: pluck(f, d, 0.6, 1.2))
    pads(s, buf, prog, -1, 0.9, 1400)
    bassline(s, buf, prog, -2, 0.7, pattern=(0,))
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (2.5, lambda: frame_drum(s.rng, False))], 0.5)
    finish_track("title", buf, 2.4, 0.33)


def track_grassland():
    s = Song(67, "mixolydian", 108, seed=21)  # G mixolydian: open road
    prog = [0, 3, 6, 0, 0, 3, 4, 4, 5, 3, 0, 4, 0, 3, 6, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, FLOWING, start=2)
    s.render_notes(buf, mel, lambda f, d: pluck(f, d, 0.8, 0.8), octave=1, gain=1.1)
    s.render_notes(buf, [(st + 0.02, l, d - 2) for st, l, d in mel[::3]], lambda f, d: flute(f, d, s.rng), octave=1, gain=0.45)
    arpeggio(s, buf, prog, 0, 0.55, pattern=(0, 2, 1, 2), step=0.5)
    bassline(s, buf, prog, -1, 0.8, pattern=(0, 2))
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (1.5, lambda: tambourine(s.rng)), (2, lambda: frame_drum(s.rng, False)),
                              (3, lambda: tambourine(s.rng)), (3.5, lambda: tambourine(s.rng))], 0.6)
    finish_track("grassland", buf, 1.6, 0.25)


def track_village():
    s = Song(65, "major", 96, beats=3, seed=31)  # F major waltz
    prog = [0, 3, 4, 0, 0, 3, 4, 4, 5, 3, 0, 4, 0, 3, 4, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, WALTZ, start=4)
    s.render_notes(buf, mel, lambda f, d: flute(f, d, s.rng, vib=4.5), octave=1, gain=0.9)
    for bar, deg in enumerate(prog):  # oom-pah-pah on the lute
        ch = s.chord(deg, 0)
        place(buf, bar * 3 * s.beat, pluck(hz(s.note(deg, -1)), s.beat * 2, 0.6, 0.9), 0.9)
        for b in (1, 2):
            for n in ch:
                place(buf, (bar * 3 + b) * s.beat, pluck(hz(n), s.beat, 0.7, 0.4), 0.3)
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (1, lambda: tambourine(s.rng)), (2, lambda: tambourine(s.rng))], 0.4)
    finish_track("village", buf, 1.2, 0.22)


def track_desert():
    s = Song(62, "hijaz", 100, seed=41)  # D hijaz: the caravan road
    prog = [0, 0, 6, 0, 3, 3, 6, 0, 0, 0, 4, 4, 3, 6, 6, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, [[0.5, 0.5, 1, 2], [1, 0.5, 0.5, 1, 1], [0.25, 0.25, 0.5, 1, 2], [2, 1, 1]], start=4)
    s.render_notes(buf, mel, lambda f, d: pluck(f, d, 0.92, 0.5), octave=1, gain=1.1)  # oud: bright, short
    s.render_notes(buf, [(st, l, d) for st, l, d in mel if l >= 1], lambda f, d: flute(f, d, s.rng, vib=6, breath=0.12), octave=1, gain=0.35)
    for bar in range(len(prog)):  # a drone on the root and fifth
        place(buf, bar * 4 * s.beat, pad([hz(s.note(0, -1)), hz(s.note(4, -1))], 4 * s.beat + 0.3, s.rng, 900), 1.1)
    dum, tek = (lambda: frame_drum(s.rng, True)), (lambda: frame_drum(s.rng, False))
    drums(s, buf, len(prog), [(0, dum), (1, tek), (1.5, tek), (2, dum), (3, tek)], 0.7)  # maqsum
    finish_track("desert", buf, 1.4, 0.24)


def track_oasis():
    s = Song(69, "harmonic", 80, seed=51)  # A harmonic minor, unhurried
    prog = [0, 3, 4, 0, 5, 3, 4, 0] * 2
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, SLOW, start=4)
    s.render_notes(buf, mel, lambda f, d: flute(f, d, s.rng, vib=5.5, breath=0.1), octave=1, gain=0.9)
    arpeggio(s, buf, prog, -1, 0.7, pattern=(0, 1, 2, 1, 2, 1, 0, 1), step=0.5, inst=lambda f, d: pluck(f, d, 0.85, 0.6))
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (2.5, lambda: frame_drum(s.rng, False)), (3, lambda: frame_drum(s.rng, False))], 0.45)
    finish_track("oasis", buf, 1.8, 0.28)


def track_ancient():
    s = Song(52, "phrygian", 66, seed=61)  # E phrygian: old stones, dust
    prog = [0, 0, 1, 0, 0, 0, 6, 1] * 2
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    pads(s, buf, prog, 0, 0.9, 1100)
    mel = s.melody(prog, [[4], [2, 2], [3, -1], [-2, 2]], start=7)
    s.render_notes(buf, mel, lambda f, d: bell(f, d + 1.5, 1.6), octave=1, gain=0.8)
    s.render_notes(buf, [(st + 2, l, d + 2) for st, l, d in mel[::2]], lambda f, d: pluck(f, d + 0.8, 0.5, 1.5), octave=0, gain=0.6)
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (3, lambda: frame_drum(s.rng, True))], 0.6)
    finish_track("ancient", buf, 3.0, 0.4)


def track_north():
    s = Song(50, "minor", 72, seed=81)  # D minor: snow, wind and old songs
    prog = [0, 0, 5, 6, 0, 3, 4, 0, 5, 5, 3, 6, 0, 3, 4, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    for bar in range(len(prog)):  # a low drone on the root and fifth, like a bowed lyre
        place(buf, bar * 4 * s.beat, pad([hz(s.note(0, -1)), hz(s.note(4, -1))], 4 * s.beat + 0.3, s.rng, 700), 1.0)
    mel = s.melody(prog, SLOW + [[1.5, 0.5, 2]], start=4)
    s.render_notes(buf, mel, lambda f, d: brass(f, d), octave=0, gain=0.55)  # a horn
    s.render_notes(buf, [(st + 0.5, l, d + 4) for st, l, d in mel[::2]], lambda f, d: bell(f, d + 1.0, 1.4), octave=1, gain=0.35)  # ice
    pads(s, buf, prog, 0, 0.6, 1200)
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (0.5, lambda: frame_drum(s.rng, True))], 0.55)  # a slow heartbeat
    finish_track("north", buf, 2.6, 0.36)


def track_hall():
    s = Song(62, "dorian", 104, beats=3, seed=91)  # D dorian in three: the mead hall
    prog = [0, 6, 3, 0, 0, 6, 4, 4, 3, 6, 0, 4, 0, 6, 3, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, WALTZ, start=4)
    s.render_notes(buf, mel, lambda f, d: flute(f, d, s.rng, vib=4.0, breath=0.09), octave=1, gain=0.8)
    s.render_notes(buf, mel, lambda f, d: pluck(f, d, 0.7, 0.6), octave=0, gain=0.5)
    for bar, deg in enumerate(prog):
        place(buf, bar * 3 * s.beat, pluck(hz(s.note(deg, -1)), s.beat * 2.5, 0.6, 1.0), 0.9)
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (1, lambda: frame_drum(s.rng, False)), (2, lambda: frame_drum(s.rng, False))],
          0.55)
    finish_track("hall", buf, 1.4, 0.25)


def track_mediterranean():
    s = Song(64, "mixolydian", 118, beats=3, seed=101)  # E mixolydian in three: sun, sea and olive groves
    prog = [0, 6, 3, 0, 0, 6, 4, 4, 5, 3, 6, 0, 0, 3, 6, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, WALTZ + [[0.5, 0.5, 1, 1]], start=4)
    s.render_notes(buf, mel, lambda f, d: pluck(f, d, 0.95, 0.45), octave=1, gain=1.0)  # a bright lyre
    s.render_notes(buf, [(st, l, d + 2) for st, l, d in mel if l >= 1], lambda f, d: flute(f, d, s.rng, vib=5.0), octave=1, gain=0.4)
    arpeggio(s, buf, prog, 0, 0.5, pattern=(0, 1, 2), step=1.0, inst=lambda f, d: pluck(f, d, 0.7, 0.8))
    bassline(s, buf, prog, -1, 0.7, pattern=(0,))
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (1, lambda: tambourine(s.rng)), (2, lambda: tambourine(s.rng))], 0.5)
    finish_track("mediterranean", buf, 1.8, 0.28)


def track_harbor():
    s = Song(69, "major", 84, seed=111)  # A major, unhurried: a white village by the sea
    prog = [0, 3, 4, 0, 5, 3, 1, 4] * 2
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, SLOW + FLOWING[:2], start=4)
    s.render_notes(buf, mel, lambda f, d: flute(f, d, s.rng, vib=4.5, breath=0.07), octave=1, gain=0.85)
    arpeggio(s, buf, prog, 0, 0.6, pattern=(0, 1, 2, 1), step=0.5, inst=lambda f, d: pluck(f, d, 0.8, 0.9))
    pads(s, buf, prog, -1, 0.5, 1500)
    bassline(s, buf, prog, -1, 0.6, pattern=(0, 2))
    finish_track("harbor", buf, 1.6, 0.26)


def track_unholy():
    s = Song(50, "harmonic", 60, seed=121)  # D harmonic minor, slow: dead woods under a red moon
    prog = [0, 0, 5, 4, 0, 3, 4, 4, 5, 3, 1, 4, 0, 5, 4, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    pads(s, buf, prog, -1, 1.0, 900)  # a dark organ
    pads(s, buf, prog, 0, 0.5, 1400)
    mel = s.melody(prog, SLOW + [[3, 1], [2, 1, 1]], start=4)
    s.render_notes(buf, mel, lambda f, d: bell(f, d + 1.2, 1.3), octave=1, gain=0.55)
    for bar in range(0, len(prog), 2):  # a low bell tolling every other bar
        place(buf, bar * 4 * s.beat, bell(hz(s.note(0, -2)), 4.0, 2.2), 0.7)
    drums(s, buf, len(prog), [(0, lambda: frame_drum(s.rng, True)), (0.4, lambda: frame_drum(s.rng, True))], 0.5)  # a heartbeat
    finish_track("unholy", buf, 3.2, 0.42)


def track_chapel():
    s = Song(57, "minor", 78, beats=3, seed=131)  # A minor in three: a mournful village waltz
    prog = [0, 3, 4, 0, 5, 3, 4, 4, 0, 3, 6, 2, 5, 3, 4, 0]
    prog = prog + prog
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, WALTZ, start=4)
    s.render_notes(buf, mel, lambda f, d: pluck(f, d, 0.6, 0.9), octave=1, gain=0.9)
    s.render_notes(buf, [(st, l, d) for st, l, d in mel if l >= 1], lambda f, d: flute(f, d, s.rng, vib=5.5, breath=0.1), octave=0, gain=0.35)
    for bar, deg in enumerate(prog):
        place(buf, bar * 3 * s.beat, pluck(hz(s.note(deg, -1)), s.beat * 2.5, 0.5, 1.2), 0.8)
    pads(s, buf, prog, -1, 0.5, 1000)
    finish_track("chapel", buf, 2.0, 0.32)


def track_fight(name="fight", root=57, bpm=140, seed=71, elite=False):
    s = Song(root, "harmonic" if elite else "minor", bpm, seed=seed)
    prog = [0, 5, 3, 4] * 4 + [5, 3, 0, 4] * 2 + [0, 5, 3, 4] * 2 if not elite else [0, 0, 5, 4, 0, 0, 3, 4] * 2 + [5, 5, 3, 4, 0, 0, 1, 4] * 2
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, DRIVING, start=4)
    s.render_notes(buf, mel, brass, octave=1, gain=0.9, legato=0.9)
    for bar, deg in enumerate(prog):  # driving eighth-note bass
        for i in range(8):
            place(buf, (bar * 4 + i * 0.5) * s.beat, bass(hz(s.note(deg, -1)), s.beat * 0.45, "saw"), 0.55)
        ch = [hz(n) for n in s.chord(deg, 0)]
        for b in (0, 1.5, 3) if not elite else (0, 1, 2, 3):  # string stabs
            place(buf, (bar * 4 + b) * s.beat, pad(ch, s.beat * 0.6, s.rng, 3000), 1.4)
    k, sn, ht = (lambda: kick(s.rng)), (lambda: snare(s.rng)), (lambda: hat(s.rng))
    pattern = [(0, k), (1, sn), (2, k), (2.5, k), (3, sn)] + [(i * 0.5, ht) for i in range(8)]
    drums(s, buf, len(prog), pattern, 0.8)
    if elite:
        for bar, deg in enumerate(prog):
            if bar % 2 == 0:
                place(buf, bar * 4 * s.beat, timpani(hz(s.note(deg, -2)), s.rng), 0.9)
    finish_track(name, buf, 1.0, 0.18)


def track_sad():
    s = Song(62, "minor", 66, seed=81)
    prog = [0, 5, 3, 4, 0, 5, 1, 4]
    buf = song_buffer(s, len(prog))
    mel = s.melody(prog, SLOW, start=4)
    s.render_notes(buf, mel, lambda f, d: flute(f, d, s.rng, vib=4.0), octave=1, gain=0.9)
    pads(s, buf, prog, -1, 1.1, 1200)
    arpeggio(s, buf, prog, 0, 0.4, pattern=(0, 1, 2, 1), step=1, inst=lambda f, d: pluck(f, d, 0.5, 1.5))
    finish_track("sad", buf, 2.5, 0.35)


# ---- sound effects ----

# Short, bright blips sound louder than their peak says; these play softer.
QUIET = {"menu_move": 0.5, "menu_accept": 0.65, "menu_cancel": 0.65, "alert": 0.6}


def sfx():
    rng = np.random.default_rng(7)
    S = {}

    def blip(f, dur, kind="square", duty=0.25, tau=0.03):
        x = osc(kind, f, dur, duty) * decay(int(dur * SR), tau)
        return x * env(len(x), a=0.002, d=0, s=1, r=0.01)

    def notes(seq, inst, gap):
        return mix(*[(i * gap, inst(f)) for i, f in enumerate(seq)])

    S["menu_move"] = blip(880, 0.05, "square", 0.25, 0.02) * 0.5
    S["menu_accept"] = notes([660, 990], lambda f: blip(f, 0.09, "tri", tau=0.05), 0.06) * 0.8
    S["menu_cancel"] = notes([620, 415], lambda f: blip(f, 0.09, "tri", tau=0.05), 0.06) * 0.8
    whoosh = fft_filter(noise(0.25, rng), low=2500, high=400) * np.sin(np.linspace(0, np.pi, int(0.25 * SR))) * 0.5
    S["menu_open"] = mix((0, whoosh), (0.08, bell(1320, 0.5)), (0.12, bell(1760, 0.4) * 0.6))
    S["alert"] = notes([700, 1050], lambda f: blip(f, 0.08, "square", 0.5, 0.06), 0.07) * 0.6
    S["heal"] = reverb(notes([hz(n) for n in (72, 76, 79, 84, 88)], lambda f: bell(f, 0.9, 0.8), 0.07), 1.0, 0.35)
    S["heal_soft"] = reverb(notes([hz(n) for n in (79, 84)], lambda f: bell(f, 0.7, 0.6), 0.09), 0.8, 0.3) * 0.8
    crackle = np.zeros(int(0.6 * SR))
    for _ in range(14):
        c = fft_filter(noise(0.01, rng), high=1500) * decay(int(0.01 * SR), 0.002)
        place(crackle, rng.uniform(0, 0.55), c, rng.uniform(0.3, 1))
    roar = fft_filter(noise(0.6, rng), low=900) * env(int(0.6 * SR), a=0.1, d=0.3, s=0.3, r=0.2)
    S["light"] = roar * 0.7 + crackle * 0.6
    for i in (1, 2):
        c2 = np.zeros(int(0.35 * SR))
        for _ in range(4 + i * 2):
            c = fft_filter(noise(0.012, rng), high=1200) * decay(int(0.012 * SR), 0.003)
            place(c2, rng.uniform(0, 0.3), c, rng.uniform(0.3, 1))
        S[f"fire_crackle{i}"] = c2 * 0.8
    fan = notes([hz(n) for n in (72, 76, 79, 84)], lambda f: (osc("square", f, 0.18, 0.5) * 0.4 + osc("tri", f, 0.18)) * decay(int(0.18 * SR), 0.15), 0.1)
    S["level_up"] = reverb(mix((0, fan), (0.4, (osc("square", hz(84), 0.5, 0.5) * 0.4 + osc("tri", hz(84), 0.5)) * env(int(0.5 * SR), 0.01, 0.2, 0.6, 0.2)),
                              (0.45, bell(hz(96), 0.6) * 0.5)), 1.0, 0.25) * 0.7
    S["coins"] = mix((0, bell(1568, 0.3, 0.3)), (0.07, bell(2093, 0.4, 0.35)))
    chord = sum(osc("sine", hz(n), 1.2) for n in (72, 76, 79, 83)) * env(int(1.2 * SR), 0.3, 0.3, 0.6, 0.5)
    sparkle = notes([hz(n) for n in (96, 91, 100, 96)], lambda f: bell(f, 0.4, 0.2), 0.12)
    S["learn"] = reverb(mix((0, chord * 0.25), (0.2, sparkle * 0.5)), 1.5, 0.4)

    def thump(f0, f1, dur, tau):
        n = int(dur * SR)
        t = np.arange(n) / SR
        return np.sin(phase(f1 + (f0 - f1) * np.exp(-t / 0.03), n)) * np.exp(-t / tau)

    burst = fft_filter(noise(0.08, rng), low=3000) * decay(int(0.08 * SR), 0.02)
    S["hit"] = mix((0, thump(180, 60, 0.25, 0.08)), (0, burst * 0.7))
    S["crit"] = mix((0, thump(220, 50, 0.4, 0.12)), (0, fft_filter(noise(0.15, rng), low=5000) * decay(int(0.15 * SR), 0.04)),
                    (0.01, bell(1240, 0.5, 0.25) * 0.6))
    n = int(0.3 * SR)
    sw = noise(0.3, rng)
    S["miss"] = sweep_filter(sw, np.linspace(600, 4000, n // 1024 + 1)) * np.sin(np.linspace(0, np.pi, n)) * 0.7
    S["no_effect"] = mix((0, bell(180, 0.3, 0.08) * 1.5), (0, burst * 0.3))
    S["defeat"] = reverb(mix((0, thump(120, 40, 0.8, 0.3)), (0.05, osc("tri", np.linspace(400, 120, int(0.6 * SR)), 0.6) * decay(int(0.6 * SR), 0.25) * 0.4)), 1.2, 0.3)
    n = int(0.5 * SR)
    S["stat_up"] = reverb(mix((0, osc("sine", np.linspace(400, 1200, n), 0.5) * env(n, 0.02, 0.1, 0.7, 0.15) * 0.5),
                              (0.3, bell(1600, 0.4, 0.3) * 0.5)), 0.8, 0.25)
    S["stat_down"] = reverb(osc("sine", np.linspace(900, 300, n), 0.5) * env(n, 0.02, 0.1, 0.7, 0.15) * 0.5, 0.8, 0.25)
    t = t_of(0.6)
    S["status"] = reverb(osc("tri", 330 * (1 + 0.05 * np.sin(2 * np.pi * 9 * t)), 0.6) * env(len(t), 0.05, 0.2, 0.5, 0.2) * 0.5, 1.0, 0.3)
    t = t_of(0.8)
    dark = sum(osc("saw", f * (1 + 0.02 * np.sin(2 * np.pi * 3 * t + i)), 0.8) for i, f in enumerate((110, 116.5, 164)))
    S["curse"] = reverb(fft_filter(dark, low=900) * env(len(t), 0.2, 0.2, 0.6, 0.3) * 0.25, 1.2, 0.35)
    n = int(0.7 * SR)
    fb = sweep_filter(noise(0.7, rng), np.concatenate([np.linspace(400, 3000, n // 2048 + 1), np.linspace(3000, 800, n // 2048 + 1)]))
    S["fireball"] = mix((0, fb * env(n, 0.15, 0.2, 0.6, 0.25) * 0.8), (0.35, thump(140, 50, 0.4, 0.15) * 0.8))
    splash = fft_filter(noise(0.5, rng), low=6000, high=500) * decay(int(0.5 * SR), 0.12)
    bubbles = mix(*[(rng.uniform(0.05, 0.45), osc("sine", np.linspace(f, f * 1.8, int(0.05 * SR)), 0.05) * decay(int(0.05 * SR), 0.02))
                    for f in rng.uniform(500, 1200, 10)])
    S["water"] = mix((0, splash * 0.7), (0, bubbles * 0.5))
    choir = sum(osc("sine", hz(n) * (1 + 0.003 * np.sin(2 * np.pi * 5 * t_of(1.0) + n)), 1.0) for n in (72, 76, 79, 84))
    S["holy"] = reverb(mix((0, choir * env(int(SR), 0.15, 0.3, 0.6, 0.4) * 0.2), (0.05, bell(hz(96), 0.8, 0.5) * 0.5)), 1.8, 0.4)
    pops = mix(*[(rng.uniform(0, 0.5), osc("sine", np.linspace(f, f * 0.5, int(0.04 * SR)), 0.04) * decay(int(0.04 * SR), 0.012))
                 for f in rng.uniform(300, 900, 14)])
    rustle = fft_filter(noise(0.6, rng), low=5000, high=1500) * env(int(0.6 * SR), 0.1, 0.2, 0.4, 0.2) * 0.25
    S["nature"] = mix((0, pops * 0.7), (0, rustle))
    n = int(0.8 * SR)
    growl = fft_filter(osc("saw", np.linspace(90, 55, n), 0.8) + noise(0.8, rng) * 0.4, low=700)
    S["dark"] = reverb(growl * env(n, 0.3, 0.2, 0.6, 0.2) * 0.5, 1.4, 0.35)
    S["magic"] = reverb(notes([hz(n) for n in (79, 86, 91, 98)], lambda f: osc("sine", f, 0.2) * decay(int(0.2 * SR), 0.08), 0.05) * 0.6, 1.0, 0.35)
    twang = pluck(220, 0.4, 0.95, 0.15) * 1.5
    S["launch"] = mix((0, twang), (0.02, S["miss"] * 0.6))
    S["fire_strike"] = mix((0, S["miss"] * 0.8), (0.05, S["light"][: int(0.4 * SR)] * 0.6))
    n = int(0.22 * SR)
    sl = sweep_filter(noise(0.22, rng), np.linspace(2000, 9000, n // 1024 + 1)) * np.sin(np.linspace(0, np.pi, n)) ** 2
    S["slash"] = mix((0, sl * 0.9), (0.08, bell(2600, 0.25, 0.08) * 0.4))
    # Impacts by weapon (Audio.hit: hit_<kind>1..3, three takes so repeats don't drone). Each is a
    # body thump plus what the weapon adds: a blade's bright slice and ring, an axe's chop and
    # splinter, a mace's deep crunch and dull clank, a club's or staff's wooden knock, a
    # dagger's short tick, claws tearing, a bite's crunch, an arrow's thunk.
    def thud(f0, f1, dur, tau, p):
        return thump(f0 * p, f1 * p, dur, tau)

    def band(dur, lo, hi, tau, r):
        return fft_filter(noise(dur, r), low=hi, high=lo) * decay(int(dur * SR), tau)

    def ring(f, dur, tau, ratios=((1, 1), (2.41, 0.6), (3.93, 0.35), (5.8, 0.2))):
        t = t_of(dur)
        return sum(a * np.sin(2 * np.pi * f * k * t + k) * np.exp(-t / (tau / k ** 0.5)) for k, a in ratios) * np.clip(t / 0.001, 0, 1)

    def knock(f, dur, tau):
        t = t_of(dur)
        return (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.3 * t)) * np.exp(-t / tau)

    def flesh(r, p, tau=0.03):
        return band(0.12, 150 * p, 1300 * p, tau, r)

    def impact(kind, r, p):
        if kind == "sword":
            return mix((0, thud(160, 60, 0.25, 0.07, p) * 0.85), (0, band(0.09, 2500, 8500, 0.018, r) * 0.8),
                       (0.002, ring(2900 * p, 0.35, 0.09) * 0.22), (0.004, flesh(r, p) * 0.7))
        if kind == "axe":
            return mix((0, thud(130, 45, 0.3, 0.09, p)), (0, band(0.16, 600, 3800, 0.04, r) * 1.0),
                       (0.012, band(0.05, 2500, 7000, 0.01, r) * 0.6), (0.003, ring(1700 * p, 0.2, 0.05) * 0.18))
        if kind == "mace":
            cracks = mix(*[(r.uniform(0.0, 0.03), band(0.02, 2000, 6000, 0.004, r) * r.uniform(0.4, 0.8)) for _ in range(3)])
            return mix((0, thud(105, 36, 0.38, 0.12, p) * 1.25), (0, band(0.12, 180, 1700, 0.028, r) * 1.0),
                       (0.002, cracks * 0.6), (0.001, ring(780 * p, 0.25, 0.05, ((1, 1), (1.83, 0.7), (2.9, 0.4))) * 0.3))
        if kind == "club":
            return mix((0, thud(140, 55, 0.28, 0.08, p) * 1.0), (0, knock(300 * p, 0.2, 0.035) * 0.55),
                       (0, band(0.08, 200, 2200, 0.02, r) * 0.7))
        if kind == "staff":
            return mix((0, thud(175, 70, 0.2, 0.05, p) * 0.6), (0, knock(470 * p, 0.18, 0.03) * 0.6),
                       (0, band(0.04, 1500, 6000, 0.008, r) * 0.5))
        if kind == "dagger":
            return mix((0, thud(230, 95, 0.12, 0.03, p) * 0.4), (0, band(0.05, 4500, 12000, 0.008, r) * 0.9),
                       (0.003, ring(4300 * p, 0.2, 0.05) * 0.12), (0.002, flesh(r, p, 0.02) * 0.8))
        if kind == "claw":
            rips = mix(*[(i * 0.028 + r.uniform(0, 0.008), band(0.06, 1500 * p, 7000 * p, 0.018, r) * (1 - 0.2 * i)) for i in range(3)])
            return mix((0, thud(150, 55, 0.22, 0.06, p) * 0.7), (0, rips * 0.85), (0.01, flesh(r, p) * 0.6))
        if kind == "bite":
            crunch = mix(*[(r.uniform(0, 0.05), band(0.03, 800, 4500, 0.008, r) * r.uniform(0.5, 1)) for _ in range(5)])
            return mix((0, thud(120, 45, 0.25, 0.07, p) * 0.8), (0, crunch * 0.8), (0, flesh(r, p, 0.05) * 0.6))
        if kind == "arrow":
            # A sharp thwock: the head's click, a short punch, the shaft quivering after.
            t = t_of(0.3)
            quiver = np.sin(2 * np.pi * 150 * p * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 32 * t)) * np.exp(-t / 0.09)
            return mix((0, band(0.03, 2500, 9000, 0.004, r) * 1.0), (0, thud(240, 85, 0.18, 0.035, p) * 0.8),
                       (0.004, flesh(r, p, 0.025) * 0.7), (0.01, quiver * 0.3))
        raise ValueError(kind)

    # The bow loosing an arrow: the string's low twang and slap, the arrow hissing off.
    def bow_shot(r, p):
        t = t_of(0.35)
        f = 105 * p
        twang = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * 2 * f * t + 1) + 0.25 * np.sin(2 * np.pi * 3.1 * f * t)) * np.exp(-t / 0.07)
        slap = band(0.02, 1200, 5000, 0.003, r)
        n = int(0.3 * SR)
        hiss = sweep_filter(noise(0.3, r), np.linspace(6000, 1500, n // 1024 + 1)) * np.sin(np.linspace(0, np.pi, n)) ** 1.5
        hiss = fft_filter(hiss, high=900)
        return mix((0, slap * 0.8), (0, twang * 0.7), (0.015, hiss * 0.55))

    for i, p in enumerate((1.0, 0.92, 1.08)):
        S[f"bow_shot{i + 1}"] = bow_shot(np.random.default_rng(300 + i), p)

    # Battle Cry: a war horn, two long blasts (the low note swelling in, then a fifth up) over
    # two war-drum beats, in a big space.
    def horn(freq, dur):
        n = int(dur * SR)
        t = np.arange(n) / SR
        f = freq * (0.93 + 0.07 * np.clip(t / 0.14, 0, 1)) * (1 + 0.004 * np.sin(2 * np.pi * 5.0 * t))
        x = osc("saw", f, dur) + 0.6 * osc("saw", f * 1.005, dur) + 0.35 * osc("square", f / 2, dur)
        lows = np.linspace(260, 1500, max(1, n // 1024))[: n // 1024 + 1]
        x = sweep_filter(x, lows)
        return x * env(n, a=0.09, d=0.2, s=0.85, r=0.25) * 0.5
    buf = np.zeros(int(2.4 * SR))
    place(buf, 0.0, horn(hz(50), 0.85))
    place(buf, 0.62, horn(hz(57), 1.05))
    place(buf, 0.0, timpani(hz(38), rng, 1.0), 0.9)
    place(buf, 0.62, timpani(hz(38), rng, 1.0), 0.8)
    S["battle_cry"] = reverb(buf, 1.8, 0.35)

    # The weapon's own hit (hit_<kind>1..3): only the claw's is still played (Audio.hit's fallback
    # when a pair is missing: a druid's bear claws on bone, shells and spirits); every other
    # blow has its by-surface takes below.
    for kind in ("claw",):
        for i, p in enumerate((1.0, 0.93, 1.07)):
            S[f"hit_{kind}{i + 1}"] = impact(kind, np.random.default_rng(100 + i * 17 + len(kind)), p)

    # --- Hits by what they land on (Audio.hit: hit_<weapon>_<surface>1..3; Enemy.surface(),
    # Player.surface()). Each is the weapon's part (its edge, its mass, its own ring) and the
    # target's answer: flesh a dull thud that swallows any ring; plate armor a clang of
    # inharmonic plate modes ringing on, a scrape for edges; bone dry cracks and a hollow knock;
    # an insect's shell a sharp click and a crunchy crackle; a spirit's body of light a shimmer
    # and a rush of air. Three takes each, pitch and grain varied.
    EDGED = {"sword", "axe", "dagger", "claw"}
    MASS = {"sword": 0.8, "axe": 1.0, "mace": 1.25, "club": 1.0, "staff": 0.6, "dagger": 0.4, "arrow": 0.45, "bite": 0.7, "claw": 0.7}
    WOOD = {"club", "staff"}

    def plate(r, p, f0=520.0, tau=0.38, gain=1.0):
        """Armor struck: not a bell. A worn plate is thin and damped (strapped to a body), so
        a few low inharmonic modes die within a tenth of a second, under a noisy clank in the
        mids and the rattle of mail rings (many tiny clicks). (The first version rang high and
        long: it sounded like an instrument.)"""
        tau = min(tau, 0.45) * 0.3
        f0 = f0 * 0.55
        dur = max(0.35, tau * 4)
        t = t_of(dur)
        modes = ((1.0, 1.0), (1.37, 0.8), (1.83, 0.65), (2.51, 0.45), (3.2, 0.3))
        x = np.zeros(len(t))
        for k, a in modes:
            f = f0 * p * k * r.uniform(0.97, 1.03)
            x += a * np.sin(2 * np.pi * f * t + r.uniform(0, 6)) * np.exp(-t / (tau / k ** 0.8))
        x *= 0.5
        clank = fft_filter(noise(dur, r), low=3800, high=700) * np.exp(-t / 0.035)
        rattle = np.zeros(len(t))
        for _ in range(int(r.integers(14, 22))):
            place(rattle, r.uniform(0.0, 0.09) ** 1.4, band(0.008, 3000, 9000, 0.0015, r), r.uniform(0.2, 0.7))
        return (x + clank * 0.9 + rattle * 0.5) * np.clip(t / 0.0007, 0, 1) * gain * 0.45

    def scrape(r, dur, lo, hi):
        n = int(dur * SR)
        x = sweep_filter(noise(dur, r), np.linspace(hi, lo, n // 1024 + 1))
        x = fft_filter(x, high=lo * 0.6)
        return x * np.exp(-np.arange(n) / SR / (dur / 3)) * (0.6 + 0.4 * np.sin(2 * np.pi * r.uniform(45, 70) * np.arange(n) / SR))

    def cracks(r, count, spread, lo=1800, hi=7000, tau=0.004):
        return mix(*[(r.uniform(0, spread), band(0.03, lo, hi, tau, r) * r.uniform(0.4, 1.0)) for _ in range(count)])

    def snarl(r, p, dur=0.32):
        """A beast's snarl under a bite or a swipe: growling noise, rough at ~35 Hz."""
        n = int(dur * SR)
        t = np.arange(n) / SR
        g = fft_filter(noise(dur, r), low=900 * p, high=120) * (0.55 + 0.45 * np.sin(2 * np.pi * 35 * t) ** 2)
        g += osc("saw", 95 * p * (1 + 0.04 * np.sin(2 * np.pi * 6 * t)), dur) * 0.25
        return fft_filter(g, low=1400) * env(n, a=0.02, d=0.1, s=0.7, r=0.12)

    def shimmer(r, p, dur=0.55):
        t = t_of(dur)
        x = np.zeros(len(t))
        for _ in range(7):
            f = r.uniform(1400, 4800) * p
            x += np.sin(2 * np.pi * f * t * (1 + 0.012 * np.sin(2 * np.pi * r.uniform(5, 9) * t)) + r.uniform(0, 6)) * np.exp(-t / r.uniform(0.12, 0.3))
        return x / 7 * np.clip(t / 0.004, 0, 1)

    def wound(r, p, amount, cut):
        """The target's answer when a blow lands in flesh (what the bite taught: wet and grainy
        in the mids, no pitched or hard-attacked low thump, which knocked like wood): a wet
        splat, many tiny wet grains thinning out, a soft muddy suction; cut: how much of it is
        a cut (more splat and tearing) rather than a bruise."""
        sd = 0.16
        sn = int(sd * SR)
        splat = sweep_filter(noise(sd, r), np.geomspace(2600 * p, 380, sn // 1024 + 1))
        splat = fft_filter(splat, high=140) * np.exp(-np.arange(sn) / SR / 0.04) * np.clip(np.arange(sn) / SR / 0.003, 0, 1)
        gd2 = 0.26
        grains = np.zeros(int(gd2 * SR))
        for _ in range(int(r.integers(20, 30) + 24 * cut)):
            at = r.uniform(0, 1) ** 2.2 * 0.22
            ln = r.uniform(0.004, 0.014)
            lo = r.uniform(550, 1200) * p
            g = fft_filter(noise(ln, r), low=lo * r.uniform(1.8, 2.6), high=lo) * np.sin(np.linspace(0, np.pi, int(ln * SR)))
            place(grains, at, g, r.uniform(0.3, 1.0) * (1 - at / 0.28))
        md = 0.2
        mn = int(md * SR)
        mt = np.arange(mn) / SR
        mud = fft_filter(sweep_filter(noise(md, r), np.geomspace(2000, 650, mn // 512 + 1), block=512), high=330)
        mud *= np.interp(np.arange(mn), np.linspace(0, mn, 12), r.uniform(0.4, 1.0, 12)) \
            * np.clip(mt / 0.04, 0, 1) * np.exp(-np.clip(mt - 0.04, 0, None) / 0.055)
        tn = int(0.16 * SR)
        tear = fft_filter(noise(0.16, r), low=1900, high=280) * np.exp(-np.arange(tn) / SR / 0.04)
        return mix((0.002, splat * (0.5 + 0.6 * cut)), (0, grains * 1.0), (0.04, mud * 0.6), (0.006, tear * 0.6 * cut)) * amount

    def soft_mass(r, p, m, dur=0.22):
        """A blow's weight without a slam: low noise with a soft attack (8 ms) and a short swell."""
        n = int(dur * SR)
        t = np.arange(n) / SR
        return fft_filter(noise(dur, r), low=320 * p, high=70) * np.clip(t / 0.008, 0, 1) * np.exp(-t / 0.05) * m

    def flesh_hit(kind, r, p):
        """A weapon in flesh: mostly the wound (the target), the weapon only adding its edge,
        weight or wood."""
        if kind == "sword":
            parts = [(0, band(0.07, 2500, 8500, 0.014, r) * 0.55), (0.002, ring(2900 * p, 0.12, 0.025) * 0.05),
                     (0, soft_mass(r, p, 0.7)), (0.004, wound(r, p, 1.0, 1.0))]
        elif kind == "axe":
            parts = [(0, band(0.12, 600, 3800, 0.03, r) * 0.6), (0.012, band(0.04, 2500, 7000, 0.008, r) * 0.35),
                     (0, soft_mass(r, p, 1.1)), (0.004, wound(r, p, 1.05, 1.0))]
        elif kind == "dagger":
            parts = [(0, band(0.04, 4500, 12000, 0.007, r) * 0.55), (0, soft_mass(r, p * 1.2, 0.35, 0.14)),
                     (0.003, wound(r, p * 1.1, 0.75, 0.8))]
        elif kind == "arrow":
            t = t_of(0.25)
            quiver = np.sin(2 * np.pi * 150 * p * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 32 * t)) * np.exp(-t / 0.07)
            parts = [(0, band(0.03, 2500, 9000, 0.004, r) * 0.7), (0, soft_mass(r, p * 1.15, 0.5, 0.16)),
                     (0.003, wound(r, p * 1.1, 0.7, 0.7)), (0.012, quiver * 0.12)]
        elif kind == "claw":
            rips = mix(*[(i * 0.028 + r.uniform(0, 0.008), band(0.06, 1500 * p, 7000 * p, 0.018, r) * (1 - 0.2 * i)) for i in range(3)])
            parts = [(0, rips * 0.6), (0, soft_mass(r, p, 0.6)), (0.006, wound(r, p, 1.0, 0.9)), (0, snarl(r, p) * 0.4)]
        else:
            # Blunt (mace, club, staff): a bruise more than a cut. The weight up front, a short
            # dull squish, the club's or staff's own wood knocking faintly.
            m = {"mace": 1.3, "club": 1.0, "staff": 0.7}[kind]
            parts = [(0, soft_mass(r, p, m, 0.26)), (0.003, wound(r, p * 0.85, 0.6, 0.15)),
                     (0, band(0.06, 250, 1800, 0.02, r) * 0.45 * m)]
            if kind == "mace":
                parts.append((0.001, cracks(r, 2, 0.02, 1500, 5000, 0.003) * 0.3))
            else:
                parts.append((0, knock((300 if kind == "club" else 470) * p, 0.12, 0.02) * 0.18))
        return fft_filter(mix(*parts), high=75, order=2)

    def surface_hit(kind, surf, r, p):
        m = MASS[kind]
        edged = kind in EDGED
        wood = kind in WOOD
        if surf == "flesh":
            if kind == "bite":
                # Teeth snapping shut (a sharp double click), flesh tearing (wet mid-high noise),
                # only a soft push of the body, the snarl over it. (The first version's low
                # thump knocked like wood.)
                snap = mix((0, band(0.018, 1200, 4500, 0.003, r)), (r.uniform(0.012, 0.02), band(0.018, 1000, 3800, 0.0035, r) * 0.8))
                n = int(0.18 * SR)
                tear = fft_filter(noise(0.18, r), low=1900, high=280) * np.exp(-np.arange(n) / SR / 0.045) \
                    * (0.6 + 0.4 * np.sin(2 * np.pi * r.uniform(60, 90) * np.arange(n) / SR))
                # Deeper and meatier, never a tone (a pitched thump knocks like wood): the body's
                # push as low filtered noise, a wet squelch under the tear, a deeper snarl.
                n2 = int(0.22 * SR)
                tt = np.arange(n2) / SR
                push = fft_filter(noise(0.22, r), low=260, high=45) * np.exp(-tt / 0.06) * np.clip(tt / 0.004, 0, 1)
                # No steady rhythm anywhere (a regular flutter or a pitched growl droned): the
                # squelch is random wet grains, the growl breathy noise with an irregular swell.
                squelch = np.zeros(n2)
                for _ in range(int(r.integers(6, 10))):
                    place(squelch, r.uniform(0.0, 0.08), fft_filter(noise(0.03, r), low=650, high=110)
                          * np.exp(-np.arange(int(0.03 * SR)) / SR / 0.008), r.uniform(0.4, 1.0))
                gd = 0.26
                gn = int(gd * SR)
                wob = np.interp(np.arange(gn), np.linspace(0, gn, 9), r.uniform(0.45, 1.0, 9))
                growl = fft_filter(noise(gd, r), low=420 * p, high=60) * wob * env(gn, a=0.015, d=0.08, s=0.6, r=0.1)
                # The wound: a wet splat (noise whose brightness drops fast, liquid slapping) and
                # blood gurgling after it (short rising bubble chirps). The clicky snap quieter:
                # on its own it sounded hollow, like wood.
                sd = 0.16
                sn = int(sd * SR)
                splat = sweep_filter(noise(sd, r), np.geomspace(2600, 380, sn // 1024 + 1))
                splat = fft_filter(splat, high=140) * np.exp(-np.arange(sn) / SR / 0.04) * np.clip(np.arange(sn) / SR / 0.003, 0, 1)
                gurgle = np.zeros(int(0.3 * SR))
                for _ in range(int(r.integers(4, 7))):
                    bd = r.uniform(0.018, 0.035)
                    bn = int(bd * SR)
                    f0 = r.uniform(260, 520)
                    chirp = np.sin(phase(f0 * np.geomspace(1, r.uniform(1.8, 2.6), bn), bn)) * np.sin(np.linspace(0, np.pi, bn)) ** 2
                    place(gurgle, r.uniform(0.03, 0.22), chirp, r.uniform(0.25, 0.6))
                # (The bubbling tail came out as water: only its very start, faint, under the splat.)
                gurgle[int(0.09 * SR):] = 0.0
                # The end and the body of it: wet tissue is a grainy mid-range texture, not a low
                # burst (a low, sharp-attacked noise push slammed like a wooden door): many tiny
                # wet grains at 600-3000 Hz, dense at first and thinning out over a quarter
                # second, and a soft muddy suction in the mids. Everything under ~150 Hz cut.
                gd2 = 0.28
                grains = np.zeros(int(gd2 * SR))
                for _ in range(int(r.integers(38, 52))):
                    at = r.uniform(0, 1) ** 2.2 * 0.24
                    ln = r.uniform(0.004, 0.014)
                    lo = r.uniform(600, 1300)
                    g = fft_filter(noise(ln, r), low=lo * r.uniform(1.8, 2.6), high=lo) * np.sin(np.linspace(0, np.pi, int(ln * SR)))
                    place(grains, at, g, r.uniform(0.3, 1.0) * (1 - at / 0.3))
                md = 0.22
                mn = int(md * SR)
                mt = np.arange(mn) / SR
                mud = sweep_filter(noise(md, r), np.geomspace(2200, 700, mn // 512 + 1), block=512)
                mud = fft_filter(mud, high=350)
                mwob = np.interp(np.arange(mn), np.linspace(0, mn, 14), r.uniform(0.4, 1.0, 14))
                mud *= mwob * np.clip(mt / 0.04, 0, 1) * np.exp(-np.clip(mt - 0.04, 0, None) / 0.06)
                out = mix((0, snap * 0.35), (0.006, tear * 0.6), (0.002, splat * 0.9), (0.0, grains * 1.1),
                          (0.04, mud * 0.7), (0.01, growl * 0.4))
                return fft_filter(out, high=150, order=3)
            return flesh_hit(kind, r, p)
        if surf == "metal":
            parts = [(0, thud(150, 55, 0.25, 0.06, p) * 0.5 * m)]
            parts.append((0, band(0.025, 1500, 10000, 0.004, r) * (1.0 if not wood else 0.5)))      # the clank
            if wood:
                # Wood on steel: a dull clonk, the plate barely rings.
                parts += [(0, knock((330 if kind == "club" else 480) * p, 0.2, 0.03) * 0.7),
                          (0.001, plate(r, p, 430, 0.12, 0.6))]
            elif kind == "mace":
                parts += [(0, thud(110, 38, 0.4, 0.12, p) * 0.9), (0.001, plate(r, p, 380, 0.42, 1.25)),
                          (0.002, cracks(r, 2, 0.02) * 0.4)]
            elif kind == "arrow":
                # A glancing tink: the head skips off the plate.
                parts += [(0, plate(r, p, 900, 0.14, 0.7)), (0.003, ring(3600 * p, 0.2, 0.05) * 0.25),
                          (0.02, scrape(r, 0.08, 2500, 8000) * 0.3)]
            elif kind in ("bite", "claw"):
                parts += [(0.0, plate(r, p, 610, 0.18, 0.55)), (0.0, scrape(r, 0.22, 1800, 7500) * 0.7),
                          (0.0, snarl(r, p) * 0.45)]
                if kind == "claw":
                    parts += [(0.03, scrape(r, 0.15, 2200, 8000) * 0.5)]
            else:
                # Steel on steel: the plate's clang, the blade's own ring, an edge scraping on.
                f0 = {"sword": 560, "axe": 470, "dagger": 720}[kind]
                parts += [(0.001, plate(r, p, f0, 0.36 if kind != "dagger" else 0.2, 1.0)),
                          (0.002, ring({"sword": 2900, "axe": 1900, "dagger": 4200}[kind] * p, 0.25, 0.05) * 0.12),
                          (0.006, scrape(r, 0.12 if kind != "axe" else 0.07, 2000, 9000) * (0.45 if kind != "axe" else 0.3))]
            return reverb(mix(*parts), 0.4, 0.08, seed=int(r.integers(1000)))
        if surf == "bone":
            # Dry bone and old wrappings: a light hollow knock, sharp dry cracks, a dusty rustle.
            parts = [(0, thud(190, 80, 0.18, 0.04, p) * 0.5 * m),
                     (0, knock(760 * p, 0.15, 0.018) * 0.55),
                     (0.001, cracks(r, 3 + int(3 * m), 0.035, 1500, 6500, 0.003) * (0.7 + 0.3 * m)),
                     (0.01, band(0.18, 2500, 8000, 0.05, r) * 0.18)]
            if edged:
                parts.append((0, band(0.06, 2800, 9000, 0.012, r) * 0.6))                          # the edge biting in
            if kind == "arrow":
                parts.append((0, band(0.03, 2500, 9000, 0.004, r) * 0.8))
            return mix(*parts)
        if surf == "chitin":
            # A beetle's or spider's shell: a hard click, a crunchy crackle as it gives, a short
            # hollow resonance of the shell, a little wet squelch under it.
            t = t_of(0.12)
            shell = (np.sin(2 * np.pi * 1350 * p * t) + 0.6 * np.sin(2 * np.pi * 2280 * p * t + 1)) * np.exp(-t / 0.018)
            parts = [(0, band(0.02, 3000, 11000, 0.0025, r) * 1.0),
                     (0, shell * 0.45),
                     (0.002, cracks(r, 6 + int(4 * m), 0.045, 2200, 9000, 0.0025) * 0.7),
                     (0, thud(170, 70, 0.2, 0.045, p) * 0.55 * m),
                     (0.01, band(0.12, 250, 1500, 0.035, r) * 0.35)]
            if edged:
                parts.append((0, band(0.05, 3500, 10000, 0.01, r) * 0.5))
            return mix(*parts)
        if surf == "spirit":
            # A body of light and mist: the blow sinks in with a soft breathy "fwoosh", a low glow
            # swelling under it, a faint crackle of energy. (The first version stacked random
            # high tones: harsh.)
            dur = 0.55
            n = int(dur * SR)
            tt = np.arange(n) / SR
            breath = sweep_filter(noise(dur, r), np.linspace(700, 2600, n // 1024 + 1))
            breath = fft_filter(breath, high=250) * np.sin(np.linspace(0, np.pi, n)) ** 1.5
            glow_f = r.uniform(190, 240) * p
            glow = (np.sin(2 * np.pi * glow_f * tt) + 0.4 * np.sin(2 * np.pi * glow_f * 1.5 * tt + 1)) \
                * (1 + 0.15 * np.sin(2 * np.pi * 6 * tt)) * env(n, a=0.06, d=0.15, s=0.4, r=0.25)
            crackle = np.zeros(n)
            for _ in range(8):
                place(crackle, r.uniform(0.02, 0.35), band(0.01, 1500, 5000, 0.003, r), r.uniform(0.1, 0.35))
            parts = [(0, thud(120, 60, 0.18, 0.05, p) * 0.3 * m), (0, breath * 0.6), (0, glow * 0.18), (0, crackle * 0.5)]
            return reverb(mix(*parts), 0.9, 0.22, seed=int(r.integers(1000)))
        raise ValueError(surf)

    pairs = [(k, s) for k in ("sword", "axe", "mace", "club", "staff", "dagger", "arrow")
             for s in ("flesh", "metal", "bone", "chitin", "spirit")]
    pairs += [(k, s) for k in ("bite", "claw") for s in ("flesh", "metal")]
    for kind, surf in pairs:
        for i, p in enumerate((1.0, 0.94, 1.06)):
            r = np.random.default_rng(500 + i * 31 + len(kind) * 7 + len(surf) * 13)
            S[f"hit_{kind}_{surf}{i + 1}"] = surface_hit(kind, surf, r, p)

    for name, x in S.items():
        if only and "sounds" not in only and name not in only:
            continue
        write_wav(out_dir / "sounds" / f"{name}.wav", normalize(x, 0.85 * QUIET.get(name, 1)))
        print("wrote", name)


TRACKS = {"title": track_title, "grassland": track_grassland, "village": track_village, "desert": track_desert, "oasis": track_oasis,
          "ancient": track_ancient, "north": track_north, "hall": track_hall, "mediterranean": track_mediterranean, "harbor": track_harbor,
          "unholy": track_unholy, "chapel": track_chapel, "fight": track_fight, "fight_elite": lambda: track_fight("fight_elite", 60, 150, 72, True),
          "sad": track_sad}

if __name__ == "__main__":
    if not only or "sounds" in only or any(n not in TRACKS for n in only):
        sfx()
    for name, make in TRACKS.items():
        if not only or name in only:
            make()
