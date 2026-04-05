# Karaoke Scoring — Research & Architecture

## Table of Contents

1. [How Professional Systems Work](#how-professional-systems-work)
2. [Our Constraints](#our-constraints)
3. [Current Implementation](#current-implementation)
4. [Voice Isolation](#voice-isolation)
5. [The 4 Scoring Modes](#the-4-scoring-modes)
6. [Pitch Oracle](#pitch-oracle)
7. [Samsung Android Mic Configuration](#samsung-android-mic-configuration)
8. [Scoring Dimensions (Research)](#scoring-dimensions-research)
9. [Reference-Based Scoring (Future)](#reference-based-scoring-future)
10. [Open Source References](#open-source-references)
11. [Academic Papers](#academic-papers)

---

## How Professional Systems Work

### SingStar (Sony)

Every song ships with a hand-crafted note track (similar to UltraStar `.txt` format) encoding the melody note-by-note. The engine compares the singer's FFT-derived pitch against that reference in real time. **Octave is ignored**: hitting the right pitch class (A, B♭, etc.) in any octave gets credit. This is how men score well on female-key songs. Scoring formula is linear semitone deviation within a tolerance window.

### Joysound / DAM (Japan)

Score three dimensions: pitch accuracy (音感), rhythm/timing (リズム感), and expressiveness/volume dynamics (表現力). DAM's LIVE DAM Ai series adds AI-based "human-like" scoring. All reference-based — MIDI melody data comes from the operator's server. Scores are 0–100; 90+ is considered skilled.

### UltraStar / Vocaluxe / AllKaraoke (Open Source SingStar Clones)

Each song has a `.txt` file:
```
: 12 4 5 Hel-    (NoteType StartBeat Length Pitch Syllable)
```
Pitch `5` = MIDI 65 (F4). Scoring: quantize singer's pitch to nearest semitone, check if it matches the note pitch **modulo octave**, apply 1-semitone tolerance. Golden notes score double. Freestyle notes (rap) score nothing.

### Yamaha Patent (US5889224A, 1999)

Uses MIDI melody data. Samples singer pitch every ~30ms. Three tolerance bands around each reference note, encodes deviation as 2-bit data. Scores pitch and volume only, not vibrato or rhythm.

### Key Takeaway

All professional systems rely on **pre-made melody reference files**. None attempt real-time melody extraction from the audio. This is the fundamental constraint we work around.

---

## Our Constraints

Frank Karaoke works with **any YouTube video** without pre-made song files. This means:

| What We Have | What We Don't Have |
|---|---|
| Phone mic (captures voice + speaker bleed) | Per-song melody reference files |
| Reference audio URL (via `youtube_explode_dart`) | Synchronized PCM of the reference audio |
| YIN pitch detection (pure Dart) | Source separation (voice vs instruments) |
| Bandpass filter (200-3500 Hz) | Beat grid / rhythm timing data |

### The Phone Mic Challenge

On Android with the built-in mic, the microphone captures:
1. The singer's voice (what we want)
2. The music from the speaker (what we don't want)
3. Room reverb and ambient noise

The singer is physically closer to the mic than the speaker, so their voice dominates — but not enough for clean separation. The bandpass filter helps by attenuating frequencies where instruments are strongest (bass below 200 Hz, treble above 3500 Hz).

---

## Current Implementation

### Audio Pipeline

```
Mic input (voice + speaker bleed)
  → Bandpass filter (200-3500 Hz IIR, attenuates instrumental frequencies)
  → YIN pitch detection (threshold 0.70 for mixed signals)
  → Pitch confidence check (reject < 0.3)
  → Singing threshold (reject low amplitude)
  → Scoring mode evaluation
  → EMA live score (alpha 0.15 for ~1s response)
  → Overlay display via JS injection
```

### Two Score Displays

- **Live score**: Exponential Moving Average of recent frame scores. Reacts to current singing within ~1 second.
- **Overall score**: Cumulative average of the entire song. Used for the end-of-song celebration.

### Playback Sync

Video play/pause/seek events are detected via JavaScript event listeners injected into the YouTube page:
- **Video pause** → scoring pauses (no ambient noise scoring)
- **Video play** → scoring resumes after 2-second delay
- **Video seek** → score resets to zero + 5-second warmup
- **5-second warmup** after every start/restart to skip initial noise

---

## Voice Isolation

### What We Tried

1. **Spectral subtraction** using reference audio — abandoned because:
   - YouTube CDN blocks `just_audio` from playing extracted URLs (non-browser UA)
   - Even with the reference, speaker EQ, room reverb, and Bluetooth delay make the reference signal too different from what the mic hears
   - Simple subtraction leaves worse artifacts than no subtraction

2. **Pre-emphasis + center clipping** — abandoned because:
   - Center clipping destroys the waveform shape that YIN needs for autocorrelation
   - Pre-emphasis amplifies noise as much as voice

### What We Use

**Bandpass filter (200-3500 Hz)**: A cascaded second-order IIR filter (Butterworth, Q=0.707) with:
- High-pass at 200 Hz: removes bass, kick drum, bass guitar from speaker bleed
- Low-pass at 3500 Hz: removes cymbals, hi-hats, high-frequency speaker noise
- Voice fundamentals (85-300 Hz) and formants (300-3000 Hz) pass through

This doesn't perfectly isolate the voice, but it significantly improves the voice-to-music ratio for pitch detection.

### Pitch Oracle (Implemented)

Instead of subtracting the reference signal, the app uses a **pitch oracle** — it knows what the music is playing at every moment, so it can distinguish singer from speaker bleed:

1. Download reference audio via `youtube_explode_dart`'s authenticated stream client
2. Decode to PCM via `audio_decoder` (Android MediaCodec)
3. Run YIN pitch detection to build a timestamped pitch timeline
4. Cache the timeline as JSON by video ID — subsequent plays load instantly
5. During scoring: compare mic pitch class vs reference pitch class (octave-agnostic)
6. If mic pitch matches reference → speaker bleed → ignore (`singerConfidence < 0.3`)
7. If mic pitch differs → singer's voice → score it

**Time sync**: The video element's `currentTime` is sent to Dart via a `timeupdate` JS event listener (~250ms updates). The oracle looks up the reference pitch at the exact playback position, correctly handling pause, seek, and speed changes.

**Caching**: Pitch timelines are saved as JSON in the app's cache directory (`pitch_oracle/<videoId>.json`). First play of a song takes 5-15 seconds to download and analyze. Same song again loads from cache instantly with no network request, eliminating YouTube rate limiting for repeated songs.

**Rate limiting**: YouTube may temporarily block `youtube_explode_dart` API calls after many requests from the same IP. When this happens, the oracle fails gracefully — scoring continues in voice-only mode. The rate limit typically clears after 15-30 minutes.

---

## The 4 Scoring Modes

All modes share the same audio pipeline (bandpass filter → YIN → confidence gate). The difference is in how they evaluate the detected pitch.

### 🎯 Pitch Match

**What it measures**: How cleanly you hold notes (pitch stability)

**How it works**: Gaussian decay based on the standard deviation of MIDI values over a ~15-frame rolling window. Steady notes (stddev < 0.3 semitones) score 85-100%. Wobbling (stddev > 2 semitones) scores near 0%.

**Best for**: Songs you know well, where you can hold notes steadily.

### 〰️ Contour

**What it measures**: How much melodic shape you create

**How it works**: Measures pitch range covered in the recent window plus significant melodic movements (> 0.5 semitone jumps). Monotone singing scores ~10%. Smooth melodic movement with 2-6 semitone range scores 70-100%.

**Best for**: Learning new songs, singing in a comfortable key.

### 📐 Intervals

**What it measures**: Musical quality of note-to-note jumps

**How it works**: Gaussian scoring curve centered at 2 semitones (whole step). Half step = 88%, third = 80%, fifth = 24%, octave jump = very low. Sustained same-note = 60%.

**Best for**: Singing in a different key, rewarding proper phrasing.

### 🔥 Streak

**What it measures**: Consistency under pressure

**How it works**: Uses Pitch Match as the base score, plus a combo multiplier. Consecutive frames above 0.4 primary score build the streak counter. The streak adds bonus points (up to +0.4 at 30+ streak). Breaking a streak > 5 frames pushes a 0.05 penalty into the EMA. Silence freezes the streak (instrumental breaks are safe).

**Best for**: Parties and competition — most dynamic and exciting.

### With vs Without Reference (Pitch Oracle)

When the pitch oracle is available:
- **Pitch Match**: Compares singer's pitch class against reference pitch class (octave-agnostic, like SingStar)
- **Contour**: Cross-correlation of singer's pitch movement vs reference pitch movement
- **Intervals**: Compares singer's semitone jumps against reference jumps
- **Streak**: Uses reference-based Pitch Match as base

When the oracle is not available (rate limited, download failed):
- All modes use voice-only analysis as described above

---

## Samsung Android Mic Configuration

### Critical Settings

```dart
RecordConfig(
  autoGain: false,     // Samsung AGC ATTENUATES the signal
  echoCancel: false,   // Uses VOICE_COMMUNICATION mode, steals audio focus
  noiseSuppress: false, // Can filter the voice along with noise
  audioInterruption: AudioInterruptionMode.none,  // Don't pause when video plays
)
```

### Why `autoGain: false` is Critical

Samsung's `AutomaticGainControl` DSP implementation targets a low RMS reference level (tuned for voice calls). On Samsung Galaxy devices, enabling AGC reduces the mic peak from ~0.06 to ~0.003 — essentially silence for pitch detection.

### Why `AudioInterruptionMode.none`

The `record` package's default `pause` mode automatically pauses the recorder when another audio source starts playing (the YouTube video). Setting to `none` keeps the recorder running regardless.

### Software Gain

Even with AGC disabled, Samsung phone mics produce low PCM levels (peak ~0.05-0.15 vs desktop mics at ~0.5-0.8). When peak < 0.01, the app applies software gain (up to 30x) to bring the signal to usable levels for YIN pitch detection.

---

## Scoring Dimensions (Research)

Based on Nakano et al. (2006) and Tsai & Lee (2012), the main dimensions of vocal quality that can be measured without reference:

### 1. Intonation / Chromatic Snap

How close each sung pitch lands to the nearest musical note (semitone). Measured as deviation in cents (100 cents = 1 semitone). Good singers: 10-20 cents. Amateur: 30-50+ cents.

**Note**: YIN's frequency resolution naturally snaps to harmonic frequencies near semitone boundaries, making this metric less discriminative than expected in practice. The current implementation uses pitch stability instead.

### 2. Pitch Stability

Standard deviation of MIDI values over a rolling window. Good singing: stddev < 0.5 semitones. Bad singing: stddev > 2 semitones.

### 3. Melodic Movement

Pitch range and direction changes over time. Monotone singing (flat pitch, no movement) is penalized. Smooth melodic movement with moderate range is rewarded.

### 4. Interval Quality

Musical quality of note-to-note jumps. Steps and thirds are "musical." Wild jumps are not. Gaussian scoring centered at the whole step (2 semitones).

### 5. Pitch Confidence (YIN CMNDF)

The YIN algorithm's CMNDF minimum value directly measures how periodic (tonal) the signal is. Clear singing: CMNDF 0.01-0.10. Speech/noise: 0.30-0.90. Used as a gate (reject < 0.3) to prevent scoring non-singing sounds.

---

## Reference-Based Scoring (Future)

### Option A: Pre-Computed Reference via UltraSinger

[UltraSinger](https://github.com/rakuri255/UltraSinger) auto-generates UltraStar `.txt` note files from songs using Demucs (source separation), basic-pitch (melody transcription), and WhisperX (lyrics alignment).

**Integration plan**: Run UltraSinger offline, cache `.txt` files by YouTube video ID, use for reference-based scoring when available.

### Option B: Pitch Oracle Enhancement

The pitch oracle is implemented with caching and video time sync. Remaining improvements:
- Cross-correlation for automatic speaker delay estimation (Bluetooth, room acoustics)
- Smarter bleed detection using energy envelope, not just pitch class matching

### Option C: ML-Based Source Separation

Use Demucs or Open-Unmix via TensorFlow Lite for real-time voice separation on mobile. Requires significant engineering (model size 20-80 MB, latency 50-200ms per frame).

---

## Open Source References

| Project | Language | Stars | Reference | URL |
|---|---|---|---|---|
| UltraStar Deluxe Play | C# | 475 | `.txt` note file | github.com/UltraStar-Deluxe/Play |
| AllKaraoke | TypeScript | 220 | `.txt` note file | github.com/Asvarox/allkaraoke |
| Vocaluxe | C# | 333 | `.txt` note file | github.com/Vocaluxe/Vocaluxe |
| Nightingale | Rust/React | 965 | Auto-generated | github.com/rzru/nightingale |
| UltraSinger | Python | 492 | Generates `.txt` | github.com/rakuri255/UltraSinger |

---

## Academic Papers

1. **Nakano et al. (2006)** — "Automatic singing skill evaluation for unknown melodies using pitch interval accuracy and vibrato features." INTERSPEECH 2006. 83.5% accuracy classifying good/poor singers without reference melody.

2. **Tsai & Lee (2012)** — "Automatic Evaluation of Karaoke Singing Based on Pitch, Volume, and Rhythm Features." IEEE TASLP. Correlation r=0.82 with human judgments.

3. **Molina et al. (2013)** — "Evaluation framework and case study for automatic singing assessment." NUS. Pitch histogram distribution analysis, Spearman correlation 0.716.

4. **Zhang (2014)** — "A Real-time Karaoke Scoring System Based on Pitch Detection." Rochester ECE.

5. **Qiu (2012)** — "Development of Scoring Algorithm for Karaoke Computer Games." DiVA.

6. **US5889224A (Yamaha, 1999)** — Karaoke scoring patent using MIDI reference with three tolerance bands.

7. **WO2010115298A1** — "Automatic Scoring Method for Karaoke Singing Accompaniment."
