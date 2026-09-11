# Retro sound effects, synthesized from scratch (in the spirit of sfxr).
#   Swooshes: noise through a band-pass filter whose pitch sweeps up.
#   Impacts:  a short noise crack plus a low "thump" that drops in pitch.
#   Voices:   a buzzy sawtooth tone through two "formant" filters, which is
#             roughly how a throat shapes a vowel ("ah", "ee", "oh").
# Output: 22050 Hz, 16-bit mono WAV files in sounds/.
import numpy as np
from scipy.signal import butter, sosfilt, lfilter
from scipy.io import wavfile

RATE = 22050
rng = np.random.default_rng(1234)

def seconds(duration):
    return np.arange(int(duration * RATE)) / RATE

def envelope(length, attack, release_curve=2.0):
    """Quick rise over `attack` (fraction of length), then a curved fall to zero."""
    t = np.linspace(0, 1, length)
    rise = np.clip(t / max(attack, 1e-4), 0, 1)
    fall = np.clip((1 - t) / max(1 - attack, 1e-4), 0, 1) ** release_curve
    return np.minimum(rise, 1) * np.where(t < attack, 1, fall)

def band_pass(signal, low, high, order=2):
    sos = butter(order, [low, high], btype="band", fs=RATE, output="sos")
    return sosfilt(sos, signal)

def low_pass(signal, cutoff, order=2):
    return sosfilt(butter(order, cutoff, btype="low", fs=RATE, output="sos"), signal)

def swept_band_pass(noise, start_hz, end_hz, width):
    """Band-pass with a moving center: filter in short blocks, cross-faded."""
    block = 256
    output = np.zeros_like(noise)
    for begin in range(0, len(noise), block):
        progress = begin / len(noise)
        center = start_hz * (end_hz / start_hz) ** progress
        low, high = max(40, center * (1 - width)), min(RATE / 2 - 100, center * (1 + width))
        chunk = band_pass(noise[max(0, begin - block): begin + block], low, high)
        piece = chunk[-min(block, len(noise) - begin):] if begin > 0 else chunk[:block]
        output[begin: begin + len(piece)] = piece
    return output

def sawtooth(frequencies):
    phase = np.cumsum(frequencies) / RATE
    return 2 * (phase - np.floor(phase + 0.5))

def formant_voice(pitch_start, pitch_end, duration, formants, growl=0.0, breath=0.15, vibrato=0.0):
    t = seconds(duration)
    pitch = pitch_start * (pitch_end / pitch_start) ** (t / duration)
    if vibrato: pitch = pitch * (1 + vibrato * np.sin(2 * np.pi * 7 * t))
    source = sawtooth(pitch) + breath * rng.standard_normal(len(t))
    if growl: source *= 1 + growl * np.sin(2 * np.pi * 32 * t)   # rough, gravelly throat
    voice = sum(gain * band_pass(source, center * 0.8, center * 1.25) for center, gain in formants)
    return voice

def thump(duration, start_hz, end_hz, noise_amount=0.4, noise_cutoff=900):
    t = seconds(duration)
    frequency = start_hz * (end_hz / start_hz) ** (t / duration)
    body = np.sin(2 * np.pi * np.cumsum(frequency) / RATE)
    noise = low_pass(rng.standard_normal(len(t)), noise_cutoff) * noise_amount
    return (body + noise) * envelope(len(t), 0.02, 3)

def place(canvas, sound, at_seconds, gain=1.0):
    start = int(at_seconds * RATE)
    end = min(len(canvas), start + len(sound))
    canvas[start:end] += sound[: end - start] * gain
    return canvas

def finish(signal, peak=0.89):
    signal = signal - np.mean(signal)
    fade = min(200, len(signal) // 4)
    signal[-fade:] *= np.linspace(1, 0, fade)          # no click at the end
    return signal / (np.max(np.abs(signal)) + 1e-9) * peak

# ---------------------------------------------------------------------------

def swing(duration, start_hz, end_hz, width):
    noise = rng.standard_normal(int(duration * RATE))
    return finish(swept_band_pass(noise, start_hz, end_hz, width) * envelope(len(noise), 0.45, 1.6))

def hit_blade():
    length = int(0.22 * RATE)
    t = seconds(0.22)
    crack = band_pass(rng.standard_normal(length), 1800, 7000) * envelope(length, 0.01, 6)
    ring = (np.sin(2 * np.pi * 2300 * t) + 0.5 * np.sin(2 * np.pi * 3400 * t)) * np.exp(-t * 28) * 0.35
    body = thump(0.22, 180, 70, 0.6, 1200) * 0.8
    return finish(crack + ring + body)

def hit_blunt():
    length = int(0.3 * RATE)
    crunch = band_pass(rng.standard_normal(length), 300, 2500) * envelope(length, 0.01, 5) * 0.6
    return finish(thump(0.3, 140, 42, 0.8, 700) * 1.3 + crunch)

def voice_with_envelope(voice, attack=0.08, curve=1.4):
    return voice * envelope(len(voice), attack, curve)

def hurt_goblin():   # a sharp "eek!"
    return finish(voice_with_envelope(formant_voice(820, 560, 0.2, [(420, 1.0), (2300, 0.8)], vibrato=0.04), 0.05))

def hurt_ogre():     # a gravelly "oof"
    return finish(voice_with_envelope(formant_voice(105, 78, 0.38, [(450, 1.0), (800, 0.7)], growl=0.6, breath=0.3), 0.06))

def hurt_player():   # a short "ugh"
    return finish(voice_with_envelope(formant_voice(210, 150, 0.22, [(650, 1.0), (1150, 0.6)], breath=0.25), 0.05))

def death_goblin():  # a long, falling shriek, then the body hits the floor
    cry = voice_with_envelope(formant_voice(900, 260, 0.6, [(400, 1.0), (2200, 0.7)], vibrato=0.06), 0.04, 1.2)
    canvas = np.zeros(int(0.95 * RATE))
    place(canvas, cry, 0.0)
    place(canvas, thump(0.25, 120, 50, 0.7, 800), 0.62, 0.35)
    return finish(canvas)

def death_ogre():    # a deep groan sinking away, then a heavy fall
    groan = voice_with_envelope(formant_voice(115, 42, 1.0, [(420, 1.0), (760, 0.6)], growl=0.8, breath=0.35), 0.08, 1.1)
    canvas = np.zeros(int(1.5 * RATE))
    place(canvas, groan, 0.0)
    place(canvas, thump(0.45, 90, 30, 1.0, 500), 1.0, 0.7)
    place(canvas, thump(0.3, 70, 30, 0.8, 400), 1.18, 0.3)   # a small bounce
    return finish(canvas)

def death_player():  # a falling cry, a fall, and a low, fading note
    cry = voice_with_envelope(formant_voice(240, 120, 0.55, [(700, 1.0), (1100, 0.6)], breath=0.3, vibrato=0.03), 0.05, 1.3)
    t = seconds(1.4)
    toll = (np.sin(2 * np.pi * 110 * t) + 0.5 * np.sin(2 * np.pi * 164.8 * t) + 0.3 * np.sin(2 * np.pi * 220 * t)) * np.exp(-t * 2.2) * 0.5
    canvas = np.zeros(int(2.1 * RATE))
    place(canvas, cry, 0.0)
    place(canvas, thump(0.3, 110, 45, 0.7, 700), 0.55, 0.45)
    place(canvas, toll, 0.65, 0.4)
    return finish(canvas)

SOUNDS = {
    "swing_light": lambda: swing(0.16, 1400, 3800, 0.35),
    "swing_blade": lambda: swing(0.22, 900, 2600, 0.4),
    "swing_heavy": lambda: swing(0.4, 260, 900, 0.5),
    "hit_blade": hit_blade,
    "hit_blunt": hit_blunt,
    "hurt_goblin": hurt_goblin,
    "hurt_ogre": hurt_ogre,
    "hurt_player": hurt_player,
    "death_goblin": death_goblin,
    "death_ogre": death_ogre,
    "death_player": death_player,
}

if __name__ == "__main__":
    for name, make in SOUNDS.items():
        samples = make()
        wavfile.write(f"sounds/{name}.wav", RATE, (samples * 32767).astype(np.int16))
        print(f"{name:14s} {len(samples) / RATE:.2f} s")
