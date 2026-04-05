# Karaoke Scoring — Research & Architecture

## Table of Contents

1. [How Professional Systems Work](#how-professional-systems-work)
2. [Our Constraints](#our-constraints)
3. [Scoring Architecture](#scoring-architecture)
4. [Voice Isolation from Mixed Mic Input](#voice-isolation-from-mixed-mic-input)
5. [Latency & Sync Considerations](#latency--sync-considerations)
6. [Scoring Dimensions](#scoring-dimensions)
7. [Reference-Based Scoring (Future)](#reference-based-scoring-future)
8. [Open Source References](#open-source-references)
9. [Academic Papers](#academic-papers)

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

### US5719344A (Budget Machines)

Compares frame energy patterns (not pitch) between singer and original artist using XOR of quantized energy. Detects "is the singer making sound when the reference has sound." Very crude — this is what cheap karaoke machines without MIDI do.

### Gaudio Lab TrueScore

Separates the original artist's vocals from the full mix using source-separation ML (GSEP model), then uses extracted vocals as the reference. Covers pitch, timing, vibrato. Requires GPU — not real-time on mobile.

---

## Our Constraints

### What We Have

| Platform | Mic Input | Reference Audio | Notes |
|---|---|---|---|
| **Linux desktop** | USB mic or built-in (clean signal) | YouTube video plays through webview, no PCM access | Mic gets clean voice only |
| **Android + external mic** | Bluetooth or wired mic (clean signal) | `just_audio` plays extracted audio, full PCM access | Best setup — clean voice + clean reference |
| **Android + built-in mic** | Device mic (picks up EVERYTHING) | `just_audio` plays audio through speaker | Mic captures voice + music + room echo + speaker effects |
| **Android + JBL PartyBox** | Device mic (picks up room) | Audio plays through JBL via Bluetooth | Mic hears voice + loud speaker output with JBL effects |

### The Core Challenge

On Android with the device's built-in mic, the microphone captures:
1. The singer's voice
2. The music coming from the speaker/JBL
3. Room reverb and echo
4. Speaker processing effects (bass boost, EQ)
5. Bluetooth audio delay (100-300ms typical)

The extracted reference audio (from `youtube_explode_dart` → `just_audio`) is the **clean instrumental track**. The mic input is the **dirty mix of voice + that same instrumental + room acoustics**.

---

## Scoring Architecture

### Current: Reference-Free Scoring (Nakano et al. 2006)

Works on all platforms without any reference comparison. Scores the singer's vocal quality in absolute terms.

```
score = chromatic_snap * 0.40
      + pitch_stability * 0.30
      + presence        * 0.15
      + dynamics        * 0.15
```

| Dimension | What It Measures | How |
|---|---|---|
| Chromatic snap | How cleanly the singer lands on musical note boundaries | Deviation in cents from nearest semitone. 0 cents = perfect, 50 cents = half-semitone off |
| Pitch stability | Whether the singer holds notes steadily | Rolling stddev of MIDI note values over ~500ms. Low = stable |
| Presence | Fraction of time actually singing | Voiced frames / total frames. Instrumental breaks are skipped |
| Dynamics | Natural volume variation | RMS stddev over ~2s. Rewards moderate variation, penalizes flat screaming or near-silence |

**Pros**: Works everywhere, no reference needed, correlates r=0.82 with human judgments.
**Cons**: Can't tell if the singer is singing the RIGHT notes for THIS song. A technically perfect rendition of the wrong melody scores high.

### Future: Reference-Based Scoring

When we have a reference melody (either from `just_audio` PCM or a pre-generated note file), the scoring becomes:

```
score = pitch_match     * 0.50   (semitone distance to reference, octave-agnostic)
      + rhythm_match    * 0.20   (onset timing vs reference onsets)
      + stability       * 0.15   (same as reference-free)
      + dynamics        * 0.15   (same as reference-free)
```

---

## Voice Isolation from Mixed Mic Input

When the Android mic picks up voice + music together, we need to isolate the voice before scoring. Since we have the clean reference audio (from `just_audio`), we can use it for subtraction.

### Approach 1: Spectral Subtraction (Simple, Real-Time)

1. Compute FFT of mic input (voice + music)
2. Compute FFT of reference audio (music only, from `just_audio`)
3. Subtract reference magnitude spectrum from mic spectrum
4. The residual is approximately the voice

```
voice_spectrum ≈ |mic_fft| - α * |reference_fft|
```

Where α is a gain factor (typically 1.0-2.0) to account for speaker volume.

**Challenges**:
- Requires time-alignment between mic and reference (see Latency section)
- Speaker EQ/effects change the frequency profile — the subtraction won't be perfect
- Room reverb smears the reference in time — simple subtraction leaves artifacts
- Works better in frequency domain than time domain

**Implementation**: Apply spectral subtraction frame-by-frame, then run pitch detection on the cleaned signal. Even imperfect subtraction helps — reducing the music by 10-20 dB dramatically improves pitch detection of the voice.

### Approach 2: Harmonic/Percussive Separation

Separate the mic input into harmonic (tonal) and percussive components using median filtering on the spectrogram. The voice is predominantly harmonic. This doesn't use the reference at all but helps isolate pitched content.

### Approach 3: ML-Based Source Separation (Future)

Use a model like Demucs (Meta) or Open-Unmix to separate voice from accompaniment in real-time. These models can run on mobile with TensorFlow Lite or ONNX Runtime, but require significant engineering:
- Model size: 20-80 MB
- Latency: 50-200ms per frame on mobile GPU
- Quality: state-of-the-art, dramatically better than spectral subtraction

**Recommendation**: Start with spectral subtraction (Approach 1) for v1. It's real-time, requires no ML models, and "good enough" for party karaoke. Upgrade to ML separation later if quality demands it.

### Approach 4: Noise Gate + Frequency Band Filtering

Simpler than spectral subtraction:
- High-pass filter the mic at 200 Hz (removes bass/drums from speaker bleed)
- The fundamental frequency of most singing is 100-800 Hz
- Music has energy spread across the full spectrum; voice energy is concentrated
- After filtering, the voice-to-music ratio improves significantly

Can be combined with spectral subtraction for better results.

---

## Latency & Sync Considerations

### Sources of Delay

| Source | Typical Delay | Notes |
|---|---|---|
| Bluetooth A2DP audio | 100-300ms | Between `just_audio` output and speaker sound |
| WebView video-to-audio sync | 0-200ms | YouTube's own buffering |
| `just_audio` ↔ WebView sync | 50-500ms | Our sync mechanism (periodic JS bridge polling) |
| Speaker processing (JBL DSP) | 10-50ms | Bass boost, EQ, spatial effects |
| Room acoustics (reverb) | 10-100ms | Sound travel + wall reflections |
| Mic capture latency | 5-20ms | `record` package → PCM buffer delivery |
| Total worst case | **175-1170ms** | Bluetooth + bad sync + room + processing |

### Impact on Scoring

For **pitch comparison** (reference vs voice), the mic input arrives AFTER the reference by the total delay. If we compare frame N of the reference with frame N of the mic, we're comparing different moments in the song.

**Solution: Cross-correlation alignment**

1. Maintain a circular buffer of the last ~2 seconds of reference audio
2. Cross-correlate the mic input against this buffer to find the lag
3. Use the lag-aligned reference frame for comparison
4. Re-compute alignment every ~5 seconds (drift correction)

```dart
// Pseudo-code for alignment
final lag = crossCorrelate(micBuffer, referenceBuffer);
// lag is in samples, convert to frames
final alignedReferenceFrame = referenceBuffer[currentFrame - lag];
```

For **reference-free scoring** (current implementation), latency doesn't matter — we only analyze the singer's voice in isolation.

### Wi-Fi Considerations

If the phone is on Wi-Fi and the YouTube video is streaming:
- Video buffering adds variable latency
- Network jitter can cause audio glitches in `just_audio`
- The `youtube_explode_dart` extracted URL may expire (typically valid for 6 hours)

**Mitigation**: Pre-buffer ~10 seconds of `just_audio` audio before starting scoring. Monitor for buffer underruns and pause scoring during glitches.

---

## Scoring Dimensions (Detailed)

### 1. Chromatic Snap / Intonation (Weight: 40%)

**What**: How close is each sung pitch to the nearest musical note (semitone)?

**How**: 
```
midi = 69 + 12 * log2(hz / 440)
nearest_note = round(midi)
deviation_cents = |midi - nearest_note| * 100
snap_score = max(0, 1 - deviation_cents / 50)
```

**Why 50 cents threshold**: A quarter-tone (50 cents) is the smallest interval most listeners perceive as "out of tune." Professional singers stay within 10-20 cents; amateur singers drift 30-50+ cents.

**Octave-agnostic**: Following SingStar's approach, we should match pitch class regardless of octave. A man singing C3 while the reference shows C5 is still "on pitch." Implementation: `deviation = (midi % 12) - (reference_midi % 12)`.

### 2. Pitch Stability (Weight: 30%)

**What**: Is the singer holding notes steadily or wobbling erratically?

**How**: Rolling standard deviation of MIDI values over ~500ms (12 frames at 100fps). Good singing: stddev < 0.5 semitones. Bad singing: stddev > 2 semitones.

**Distinction from vibrato**: Intentional vibrato is periodic (5-7 Hz) with controlled extent (±0.5-1.0 semitones). Instability is aperiodic and wider. A future enhancement could detect vibrato and reward it as a bonus.

### 3. Presence / Engagement (Weight: 15%)

**What**: Is the singer actually singing throughout the song?

**How**: `voiced_frames / total_frames` (excluding silence below noise gate).

**Important**: Instrumental breaks should not penalize. The noise gate threshold handles this — quiet frames are simply not counted in the denominator.

### 4. Volume Dynamics (Weight: 15%)

**What**: Does the singer vary their volume expressively?

**How**: Standard deviation of RMS energy over ~2-second windows. 
- Too flat (stddev < 0.005): score 0.3 — monotone shouting
- Too erratic (stddev > 0.2): score 0.4 — unstable
- Moderate variation (0.01-0.1): score 0.5-1.0 — expressive singing

### 5. Vibrato Detection (Bonus, Not Yet Implemented)

**What**: Periodic pitch modulation on held notes (5-7 Hz, ±0.5-1 semitone).

**How**: Autocorrelation of pitch contour on segments where pitch is sustained. If a clear periodicity is found in the 5-7 Hz range, award a bonus.

**Weight**: Bonus only (add up to +5 points to final score). Never penalize absence of vibrato — many excellent pop/rock singers don't use it.

### 6. Rhythm / Timing (Future, Requires Beat Grid)

**What**: Is the singer starting phrases at the right time?

**How**: 
1. Extract BPM from the instrumental track (onset detection + autocorrelation)
2. Detect vocal onsets in the mic input
3. Compare onset timing against the beat grid
4. Score based on timing accuracy (±50ms tolerance for "on beat")

**Feasibility**: BPM extraction from audio is well-studied and can be done in real-time with autocorrelation on onset strength signals. However, mapping vocal phrase onsets to specific beats requires either a reference melody or a pre-computed beat map.

---

## Reference-Based Scoring (Future)

### Option A: Pre-Computed Reference via UltraSinger

[UltraSinger](https://github.com/rakuri255/UltraSinger) auto-generates UltraStar `.txt` note files from songs using:
1. **Demucs** — separate vocals from accompaniment
2. **basic-pitch** (Spotify) — transcribe vocal melody to MIDI notes
3. **WhisperX** — align lyrics to timestamps

The output is a standard UltraStar `.txt` file that encodes every note's pitch, start beat, and duration.

**Integration plan**:
1. Run UltraSinger offline for popular karaoke tracks
2. Cache the `.txt` file by YouTube video ID
3. At runtime, check if a cached note file exists for the current video
4. If yes, use reference-based scoring (pitch match against notes)
5. If no, fall back to reference-free scoring

**Trade-offs**: Processing takes 2-20 minutes per song. Could be done server-side or as a background task on desktop. The note file is small (~5-50 KB per song).

### Option B: Real-Time Reference from `just_audio` PCM (Android Only)

On Android where `just_audio` gives us PCM access to the instrumental:
1. Run YIN pitch detection on the reference audio
2. The detected pitch is the dominant melody instrument
3. Compare against singer's pitch (octave-agnostic)

**Problem**: The instrumental may have multiple pitched instruments (guitar + piano + synth). YIN picks the dominant one, which may not be the melody. Accuracy is unreliable.

**Partial solution**: Use the reference pitch as a "hint" rather than ground truth. If the singer's pitch is within 2 semitones of the reference pitch (any octave), give a bonus. Don't penalize if they don't match — the reference might be wrong.

### Option C: Nightingale Architecture

[Nightingale](https://github.com/rzru/nightingale) pre-processes songs using:
1. Demucs stem separation → extract vocals
2. WhisperX → align lyrics and timing
3. Melody tracker → extract pitch contour

Results are stored and used for real-time scoring. This is the most complete solution but requires significant server infrastructure or powerful desktop processing.

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

1. **Nakano et al. (2006)** — "Automatic singing skill evaluation for unknown melodies using pitch interval accuracy and vibrato features." INTERSPEECH 2006. 83.5% accuracy classifying good/poor singers without reference melody. The foundation of our reference-free scoring.

2. **Tsai & Lee (2012)** — "Automatic Evaluation of Karaoke Singing Based on Pitch, Volume, and Rhythm Features." IEEE TASLP. Correlation r=0.82 with human judgments. Most comprehensive reference-free framework.

3. **Molina et al. (2013)** — "Evaluation framework and case study for automatic singing assessment." NUS. Pitch histogram distribution analysis, Spearman correlation 0.716.

4. **Zhang (2014)** — "A Real-time Karaoke Scoring System Based on Pitch Detection." Rochester ECE. Practical implementation using FFT pitch detection and frame-level scoring.

5. **Qiu (2012)** — "Development of Scoring Algorithm for Karaoke Computer Games." DiVA. Survey of karaoke scoring approaches and SingStar-like implementation.

6. **US5889224A (Yamaha, 1999)** — Karaoke scoring patent using MIDI reference with three tolerance bands.

7. **WO2010115298A1** — "Automatic Scoring Method for Karaoke Singing Accompaniment." Chinese patent covering pitch + rhythm + volume scoring.

---

## Implementation Roadmap

### Phase 1 (Current) — Reference-Free Scoring
- Chromatic snap + stability + presence + dynamics
- Works on all platforms, no reference needed
- Good for "party mode" — scores vocal quality, not melody accuracy

### Phase 2 — Voice Isolation for Android Built-in Mic
- Spectral subtraction using `just_audio` reference audio
- Cross-correlation for time alignment
- High-pass filtering at 200 Hz
- Goal: extract clean-enough voice for reliable pitch detection

### Phase 3 — Reference-Based Scoring with UltraSinger
- Offline pipeline to generate `.txt` note files from YouTube karaoke tracks
- Cache by video ID (local SQLite or server)
- Hybrid scoring: reference-based when available, reference-free fallback
- Octave-agnostic pitch matching (like SingStar)

### Phase 4 — Advanced Features
- Vibrato detection and bonus scoring
- Beat grid extraction for rhythm scoring
- ML-based source separation (Demucs via TFLite)
- Multiplayer scoring with participant tracking
- Score history and progression tracking via Drift/SQLite
