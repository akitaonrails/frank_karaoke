# Frank Karaoke

**IMPORTANT**: Always read and follow `~/.claude/CLAUDE-override.md` first. Those directives take precedence over everything below.

## What This Is

A Flutter app (desktop Linux + Android) that wraps YouTube with a real-time singing scoring overlay. Users find songs on YouTube, sing along, and get scored. See `docs/IDEA.md` for the full product vision.

## Architecture

**Dual-stream audio**: The WebView shows YouTube video (audio muted via JS), while `youtube_explode_dart` extracts the audio stream URL and `just_audio` plays it locally. This gives us PCM access to the reference audio for pitch comparison and pitch shifting. The microphone captures the singer's voice via the `record` package. Both streams go through YIN pitch detection, and the scoring engine compares them in real-time.

## Tech Stack

- **Flutter** — targeting Android + Linux desktop
- **Riverpod** — state management
- **webview_flutter** — YouTube embedding (Android); CEF-based for Linux
- **youtube_explode_dart** — extract audio stream URLs (no API key)
- **just_audio** — reference audio playback
- **record** — microphone PCM capture
- **Drift** (SQLite) — local persistence for sessions/scores

## Project Structure

```
lib/
  core/           # constants, extensions, errors
  features/
    youtube/      # WebView, audio extraction, sync service
    audio/        # mic capture, pitch detection, pitch shifting
    scoring/      # scoring engine, score models
    overlay/      # pitch bars, score display, session banner
    session/      # session manager, participants, persistence
    cast/         # Chromecast
    bluetooth/    # BT audio routing
    settings/     # app settings
  ui/
    screens/      # home, session, history, settings
    widgets/      # reusable UI components
    theme/        # colors, typography
  state/          # Riverpod providers
```

## Commands

```bash
flutter analyze              # static analysis (must pass with zero warnings)
flutter test                 # run all tests
flutter run -d linux         # run on desktop (dev/testing)
flutter run -d <device_id>   # run on Android device
flutter build apk            # build Android APK
```

## Development Rules

- **Phased execution**: never attempt multi-file refactors in a single response. Complete one phase, verify, get approval before the next. Max 5 files per phase.
- **Verify before "done"**: run `flutter analyze`, `flutter test`, and manual smoke test before claiming any task is complete.
- **Platform parity**: every feature must work on both Android and Linux desktop. If a package is Android-only, document the limitation and provide a stub/fallback for Linux.
- **UI principles**: big buttons, big numbers/scores/names, modern, intuitive for non-tech users. No clutter. Semi-transparent overlay that doesn't hide video lyrics.
- **Audio pipeline is the core**: the dual-stream architecture (WebView video + separate audio playback + mic capture) is the foundation. All scoring depends on it. Don't break the sync.
- **YIN pitch detection**: use YIN algorithm for both reference and singer pitch extraction. Pure Dart first, move to native FFI only if performance requires it.
- **Scoring tolerance**: err on the generous side (~2 semitones tolerance). This is a party app, not a vocal coach.
