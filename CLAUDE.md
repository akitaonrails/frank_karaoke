# Frank Karaoke

**IMPORTANT**: Always read and follow `~/.claude/CLAUDE-override.md` first. Those directives take precedence over everything below.

## What This Is

A Flutter app (Android) that wraps YouTube with a real-time singing scoring overlay. Users find songs on YouTube, sing along, and get scored. See `docs/IDEA.md` for the original product vision and `docs/scoring.md` for the scoring research.

## Architecture

The app is a full-screen Android WebView loading YouTube. All scoring UI (pitch trail, score display, settings panel, mode selector) is injected as HTML/CSS/JS into the YouTube page via `webview_flutter`'s JavaScript bridge.

**Audio pipeline**: The microphone captures audio via the `record` package. A bandpass filter (200-3500 Hz) isolates vocal frequencies from speaker bleed. The YIN algorithm detects pitch. The scoring session evaluates quality using one of 4 pluggable scoring modes.

**Pitch oracle** (when available): Downloads the video's audio via `youtube_explode_dart`, decodes to PCM via `audio_decoder` (Android MediaCodec), and builds a pitch timeline. Used to distinguish singer's voice from speaker bleed by comparing pitch classes.

## Tech Stack

- **Flutter** — targeting Android
- **Riverpod** — state management
- **webview_flutter** — YouTube embedding
- **youtube_explode_dart** — extract audio stream URLs (no API key)
- **record** — microphone PCM capture
- **audio_decoder** — reference audio decoding (Android MediaCodec)
- **shared_preferences** — settings persistence

## Project Structure

```
lib/
  core/           # constants, audio presets, scoring modes, logo assets
  features/
    audio/        # mic capture, pitch detection, bandpass filter, voice isolation, pitch oracle
    scoring/      # scoring engine (hzToMidi etc), scoring session (multi-mode)
    overlay/      # HTML/CSS/JS overlay generation (all injected into webview)
    youtube/      # webview widget, audio extraction service, URL parser
  state/          # Riverpod providers
  ui/
    screens/      # home screen (just the webview)
    theme/        # dark theme
docs/
  IDEA.md         # original product vision
  scoring.md      # comprehensive scoring research
  screenshots/    # app screenshots
```

## Commands

```bash
flutter analyze              # static analysis (must pass with zero warnings)
flutter test                 # run all tests
flutter run -d <device_id>   # run on Android device
flutter build apk --debug    # build debug APK for sideloading
```

## Development Rules

- **Android-only**: No Linux desktop support. The WebView and mic capture are Android-specific.
- **Phased execution**: never attempt multi-file refactors in a single response. Complete one phase, verify, get approval before the next. Max 5 files per phase.
- **Verify before "done"**: run `flutter analyze`, `flutter test`, and test on device before claiming any task is complete.
- **Assume hardware works**: When something doesn't work on a device, the problem is our code configuration, not the OS or hardware. Research documentation before trying random fixes.
- **Research before implementing**: For non-trivial features, present a plan before writing code. Don't trial-and-error — check documentation first.
- **UI via JS injection**: All overlay UI (scoring, settings, mode selector) is injected as HTML/CSS/JS into the YouTube webview. Flutter widgets can't render on top of the webview.
- **Samsung mic config**: `autoGain: false` is critical on Samsung devices — Samsung's AGC DSP attenuates the mic signal. `AudioInterruptionMode.none` prevents the recorder from pausing when video audio plays.
- **YouTube rate limiting**: `youtube_explode_dart` API calls can trigger rate limiting. Cache results and minimize API calls. The pitch oracle downloads may fail temporarily.
- **Scoring is approximate**: Without per-song melody reference files, scoring measures vocal quality (stability, intonation, musicality), not melody accuracy. See `docs/scoring.md`.

## Key Technical Decisions

- **No separate audio player**: `just_audio` was removed — YouTube's CDN blocks non-browser user agents, preventing direct audio playback. The webview handles all audio.
- **Bandpass filter for voice isolation**: Instead of spectral subtraction (which requires perfectly synced reference audio), a 200-3500 Hz IIR filter attenuates instrumental frequencies from speaker bleed.
- **YIN threshold 0.70**: Relaxed from the standard 0.15 because the phone mic captures mixed voice+music. Higher threshold accepts less confident pitch detections.
- **5-second warmup**: Scoring waits 5 seconds after playback starts to avoid scoring initial clicks and noise.
- **Playback sync via JS bridge**: Video play/pause/seek events are detected via JavaScript event listeners and synced to the scoring session.
- **Pitch shift via playbackRate**: Uses `video.playbackRate` with `preservesPitch=false` to shift the YouTube audio pitch. Combined with scoring pitch offset so both audio and scoring adjust together. No external audio library needed.
