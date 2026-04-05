/// JavaScript to inject a scoring overlay into the YouTube webview.
///
/// Uses DOM createElement (not innerHTML) to comply with YouTube's
/// Trusted Types Content Security Policy.
class WebviewOverlay {
  static String injectOverlayJs({required String singerName}) => '''
    (function() {
      var existing = document.getElementById('fk-overlay');
      if (existing) existing.remove();

      var overlay = document.createElement('div');
      overlay.id = 'fk-overlay';

      // Song title (top left, with mic icon)
      var singer = document.createElement('div');
      singer.id = 'fk-singer';
      singer.textContent = '$singerName';
      singer.style.cssText = 'position:fixed;top:14px;left:14px;z-index:99999;'
        + 'background:linear-gradient(135deg,rgba(108,92,231,0.85),rgba(0,0,0,0.7));'
        + 'color:#fff;padding:10px 18px;border-radius:24px;'
        + 'font-family:system-ui,sans-serif;font-size:14px;font-weight:600;'
        + 'pointer-events:none;max-width:45%;'
        + 'overflow:hidden;text-overflow:ellipsis;white-space:nowrap;'
        + 'box-shadow:0 2px 20px rgba(108,92,231,0.4);';
      overlay.appendChild(singer);

      // Mic activity dot (pulses when mic is picking up sound)
      var micDot = document.createElement('div');
      micDot.id = 'fk-mic-dot';
      micDot.style.cssText = 'position:fixed;top:18px;right:80px;z-index:99999;'
        + 'width:12px;height:12px;border-radius:50%;background:#333;'
        + 'pointer-events:none;transition:all 0.1s ease-out;'
        + 'box-shadow:0 0 0 rgba(0,210,255,0);';
      overlay.appendChild(micDot);

      // Score display (bottom right, with glow)
      var scoreBox = document.createElement('div');
      scoreBox.id = 'fk-score';
      scoreBox.style.cssText = 'position:fixed;bottom:24px;right:24px;z-index:99999;'
        + 'background:rgba(0,0,0,0.8);padding:16px 24px;border-radius:20px;'
        + 'font-family:system-ui,sans-serif;text-align:center;pointer-events:none;'
        + 'border:2px solid rgba(0,210,255,0.3);min-width:110px;'
        + 'box-shadow:0 4px 30px rgba(0,210,255,0.2);'
        + 'transition:box-shadow 0.3s ease;';

      var scoreLabel = document.createElement('div');
      scoreLabel.style.cssText = 'font-size:10px;color:rgba(255,255,255,0.4);'
        + 'letter-spacing:3px;margin-bottom:4px;font-weight:500;';
      scoreLabel.textContent = 'SCORE';
      scoreBox.appendChild(scoreLabel);

      var scoreValue = document.createElement('div');
      scoreValue.id = 'fk-score-value';
      scoreValue.style.cssText = 'font-size:52px;font-weight:800;line-height:1;'
        + 'color:#00d2ff;text-shadow:0 0 20px rgba(0,210,255,0.6);'
        + 'transition:color 0.3s ease,text-shadow 0.3s ease;';
      scoreValue.textContent = '0';
      scoreBox.appendChild(scoreValue);

      overlay.appendChild(scoreBox);

      // Pitch trail canvas (bottom left, scrolling visualization)
      var pitchCanvas = document.createElement('canvas');
      pitchCanvas.id = 'fk-pitch-canvas';
      pitchCanvas.width = 360;
      pitchCanvas.height = 72;
      pitchCanvas.style.cssText = 'position:fixed;bottom:24px;left:24px;z-index:99999;'
        + 'pointer-events:none;border-radius:16px;'
        + 'background:rgba(0,0,0,0.7);'
        + 'border:1px solid rgba(108,92,231,0.3);'
        + 'box-shadow:0 4px 30px rgba(0,0,0,0.4);';
      overlay.appendChild(pitchCanvas);

      document.body.appendChild(overlay);

      window._fkPitchTrail = [];
      window._fkPitchMax = 360;
    })();
  ''';

  static String updateScoreJs(int score) {
    // Score color: blue < 50, green 50-79, gold 80+
    String color;
    String glow;
    if (score >= 80) {
      color = '#ffd700';
      glow = '0 0 30px rgba(255,215,0,0.7)';
    } else if (score >= 50) {
      color = '#00ff88';
      glow = '0 0 20px rgba(0,255,136,0.5)';
    } else {
      color = '#00d2ff';
      glow = '0 0 20px rgba(0,210,255,0.4)';
    }
    return '''
      (function() {
        var el = document.getElementById('fk-score-value');
        if (!el) return;
        el.textContent = '$score';
        el.style.color = '$color';
        el.style.textShadow = '$glow';
        var box = document.getElementById('fk-score');
        if (box) box.style.boxShadow = '0 4px 30px ' + '$color'.replace(')', ',0.25)').replace('rgb', 'rgba');
      })();
    ''';
  }

  /// Push a pitch point to the scrolling trail and redraw with glow.
  static String updatePitchTrailJs(double normalizedPitch, double quality) {
    final p = normalizedPitch.clamp(0.0, 1.0).toStringAsFixed(3);
    final q = quality.clamp(0.0, 1.0).toStringAsFixed(3);
    return '''
      (function() {
        var canvas = document.getElementById('fk-pitch-canvas');
        if (!canvas || !window._fkPitchTrail) return;
        var trail = window._fkPitchTrail;
        trail.push({p: $p, q: $q});
        if (trail.length > window._fkPitchMax) trail.shift();

        var ctx = canvas.getContext('2d');
        var w = canvas.width, h = canvas.height;
        ctx.clearRect(0, 0, w, h);

        // Subtle grid lines
        ctx.strokeStyle = 'rgba(255,255,255,0.04)';
        ctx.lineWidth = 1;
        for (var j = 0.25; j < 1; j += 0.25) {
          ctx.beginPath();
          ctx.moveTo(0, h * j);
          ctx.lineTo(w, h * j);
          ctx.stroke();
        }

        // Draw connected pitch trail with glow
        var startX = w - trail.length;
        var prevX = -1, prevY = -1;

        for (var i = 0; i < trail.length; i++) {
          var pt = trail[i];
          if (pt.p <= 0) { prevX = -1; continue; }
          var x = startX + i;
          var y = h - (pt.p * (h - 10)) - 5;

          // Color: red(miss) -> yellow(ok) -> green(good)
          var r = Math.round(255 * (1 - pt.q));
          var g = Math.round(200 * pt.q + 55);
          var col = 'rgb(' + r + ',' + g + ',80)';

          // Draw connecting line
          if (prevX >= 0 && Math.abs(prevY - y) < h * 0.5) {
            ctx.strokeStyle = col;
            ctx.lineWidth = 2;
            ctx.globalAlpha = 0.6;
            ctx.beginPath();
            ctx.moveTo(prevX, prevY);
            ctx.lineTo(x, y);
            ctx.stroke();
            ctx.globalAlpha = 1.0;
          }

          // Draw dot with glow
          ctx.shadowColor = col;
          ctx.shadowBlur = pt.q > 0.5 ? 8 : 3;
          ctx.fillStyle = col;
          ctx.beginPath();
          ctx.arc(x, y, pt.q > 0.5 ? 3 : 2, 0, 6.283);
          ctx.fill();
          ctx.shadowBlur = 0;

          prevX = x;
          prevY = y;
        }
      })();
    ''';
  }

  /// Update the mic activity dot — glows cyan when active.
  static String updateRmsJs(double normalizedRms) {
    final intensity = (normalizedRms * 100).clamp(0, 100).toStringAsFixed(0);
    return '''
      (function() {
        var dot = document.getElementById('fk-mic-dot');
        if (!dot) return;
        var n = $intensity / 100;
        if (n > 0.1) {
          var size = 10 + n * 6;
          dot.style.width = size + 'px';
          dot.style.height = size + 'px';
          dot.style.background = 'rgb(0,' + Math.round(180 + n*75) + ',255)';
          dot.style.boxShadow = '0 0 ' + Math.round(n*20) + 'px rgba(0,210,255,' + (n*0.8).toFixed(2) + ')';
        } else {
          dot.style.width = '10px';
          dot.style.height = '10px';
          dot.style.background = '#333';
          dot.style.boxShadow = 'none';
        }
      })();
    ''';
  }

  static String updateSingerJs(String name) => '''
    (function() {
      var el = document.getElementById('fk-singer');
      if (el) el.textContent = '$name';
    })();
  ''';

  static const removeOverlayJs = '''
    (function() {
      var el = document.getElementById('fk-overlay');
      if (el) el.remove();
      delete window._fkPitchTrail;
      delete window._fkPitchMax;
    })();
  ''';
}
