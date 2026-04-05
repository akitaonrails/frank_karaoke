/// JavaScript to inject a scoring overlay into the YouTube webview.
///
/// Creates a floating overlay with:
/// - Current singer name (top left)
/// - Real-time score (bottom right)
/// - Pitch indicator bar (right edge)
/// Semi-transparent so lyrics remain visible.
class WebviewOverlay {
  /// Inject the overlay container into the page.
  static String injectOverlayJs({required String singerName}) => '''
    (function() {
      // Remove existing overlay if any.
      const existing = document.getElementById('fk-overlay');
      if (existing) existing.remove();

      const overlay = document.createElement('div');
      overlay.id = 'fk-overlay';
      overlay.innerHTML = `
        <div id="fk-singer" style="
          position: fixed; top: 12px; left: 12px; z-index: 99999;
          background: rgba(0,0,0,0.7); color: #fff;
          padding: 8px 16px; border-radius: 8px;
          font-family: sans-serif; font-size: 16px; font-weight: 600;
          pointer-events: none; backdrop-filter: blur(4px);
          border: 1px solid rgba(108,92,231,0.5);
        ">
          🎤 $singerName
        </div>

        <div id="fk-score" style="
          position: fixed; bottom: 20px; right: 20px; z-index: 99999;
          background: rgba(0,0,0,0.75); color: #00d2ff;
          padding: 12px 20px; border-radius: 16px;
          font-family: sans-serif; text-align: center;
          pointer-events: none; backdrop-filter: blur(4px);
          border: 2px solid rgba(0,210,255,0.4);
          min-width: 100px;
        ">
          <div style="font-size: 11px; color: rgba(255,255,255,0.5);
            letter-spacing: 2px; margin-bottom: 2px;">SCORE</div>
          <div id="fk-score-value" style="font-size: 48px; font-weight: bold;
            line-height: 1;">0</div>
        </div>

        <div id="fk-pitch" style="
          position: fixed; right: 8px; top: 50%; z-index: 99999;
          transform: translateY(-50%);
          width: 6px; height: 120px;
          background: rgba(255,255,255,0.15); border-radius: 3px;
          pointer-events: none; overflow: hidden;
        ">
          <div id="fk-pitch-bar" style="
            position: absolute; bottom: 50%; left: 0; right: 0;
            height: 8px; background: #00d2ff; border-radius: 3px;
            transition: bottom 0.1s ease-out;
          "></div>
        </div>
      `;
      document.body.appendChild(overlay);
    })();
  ''';

  /// Update the score display.
  static String updateScoreJs(int score) => '''
    (function() {
      const el = document.getElementById('fk-score-value');
      if (el) el.textContent = '$score';
    })();
  ''';

  /// Update the pitch indicator bar position.
  /// [normalizedPitch] is 0.0 (low) to 1.0 (high).
  static String updatePitchJs(double normalizedPitch) {
    final pct = (normalizedPitch * 100).clamp(0, 100).toStringAsFixed(1);
    return '''
      (function() {
        const bar = document.getElementById('fk-pitch-bar');
        if (bar) bar.style.bottom = '$pct%';
      })();
    ''';
  }

  /// Update the singer name.
  static String updateSingerJs(String name) => '''
    (function() {
      const el = document.getElementById('fk-singer');
      if (el) el.textContent = '🎤 $name';
    })();
  ''';

  /// Remove the overlay from the page.
  static const removeOverlayJs = '''
    (function() {
      const el = document.getElementById('fk-overlay');
      if (el) el.remove();
    })();
  ''';
}
