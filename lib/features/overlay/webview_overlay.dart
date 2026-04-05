/// JavaScript to inject a scoring overlay into the YouTube webview.
///
/// Uses DOM createElement (not innerHTML) to comply with YouTube's
/// Trusted Types Content Security Policy.
///
/// The overlay includes:
/// - Song title (top left)
/// - Current note display + mic dot (top right area)
/// - Score with color feedback (bottom right)
/// - Dual-track pitch canvas: reference melody (from Web Audio API on the
///   video element) vs singer's voice, so users can see the gap
class WebviewOverlay {
  static String injectOverlayJs({required String singerName}) => '''
    (function() {
      var existing = document.getElementById('fk-overlay');
      if (existing) existing.remove();

      var overlay = document.createElement('div');
      overlay.id = 'fk-overlay';

      // Song title (top left)
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

      // Current note + mic indicator (top right)
      var noteBox = document.createElement('div');
      noteBox.id = 'fk-note-box';
      noteBox.style.cssText = 'position:fixed;top:14px;right:14px;z-index:99999;'
        + 'background:rgba(0,0,0,0.75);padding:8px 16px;border-radius:16px;'
        + 'font-family:system-ui,sans-serif;pointer-events:none;display:flex;'
        + 'align-items:center;gap:10px;border:1px solid rgba(0,210,255,0.3);';

      var micDot = document.createElement('div');
      micDot.id = 'fk-mic-dot';
      micDot.style.cssText = 'width:10px;height:10px;border-radius:50%;'
        + 'background:#333;transition:all 0.1s ease-out;flex-shrink:0;';
      noteBox.appendChild(micDot);

      var noteLabel = document.createElement('div');
      noteLabel.id = 'fk-note-label';
      noteLabel.style.cssText = 'color:#00d2ff;font-size:22px;font-weight:700;'
        + 'min-width:48px;text-align:center;text-shadow:0 0 10px rgba(0,210,255,0.5);';
      noteLabel.textContent = '--';
      noteBox.appendChild(noteLabel);

      overlay.appendChild(noteBox);

      // Settings gear button (below note box, clickable)
      var gearBtn = document.createElement('div');
      gearBtn.id = 'fk-settings-btn';
      gearBtn.textContent = '\\u2699';
      gearBtn.style.cssText = 'position:fixed;top:58px;right:14px;z-index:100000;'
        + 'width:40px;height:40px;border-radius:50%;'
        + 'background:rgba(0,0,0,0.7);color:rgba(255,255,255,0.6);'
        + 'font-size:22px;display:flex;align-items:center;justify-content:center;'
        + 'cursor:pointer;pointer-events:auto;'
        + 'border:1px solid rgba(255,255,255,0.15);'
        + 'transition:all 0.2s ease;';
      gearBtn.addEventListener('mouseenter', function() {
        gearBtn.style.color = '#00d2ff';
        gearBtn.style.borderColor = 'rgba(0,210,255,0.5)';
        gearBtn.style.boxShadow = '0 0 15px rgba(0,210,255,0.3)';
      });
      gearBtn.addEventListener('mouseleave', function() {
        gearBtn.style.color = 'rgba(255,255,255,0.6)';
        gearBtn.style.borderColor = 'rgba(255,255,255,0.15)';
        gearBtn.style.boxShadow = 'none';
      });
      gearBtn.addEventListener('click', function() {
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.FrankSettings) {
          window.webkit.messageHandlers.FrankSettings.postMessage('open');
        }
      });
      overlay.appendChild(gearBtn);

      // Restart button (below settings gear)
      var restartBtn = document.createElement('div');
      restartBtn.id = 'fk-restart-btn';
      restartBtn.textContent = '\\u21BB';
      restartBtn.style.cssText = 'position:fixed;top:104px;right:14px;z-index:100000;'
        + 'width:40px;height:40px;border-radius:50%;'
        + 'background:rgba(0,0,0,0.7);color:rgba(255,255,255,0.6);'
        + 'font-size:22px;display:flex;align-items:center;justify-content:center;'
        + 'cursor:pointer;pointer-events:auto;'
        + 'border:1px solid rgba(255,255,255,0.15);'
        + 'transition:all 0.2s ease;';
      restartBtn.addEventListener('mouseenter', function() {
        restartBtn.style.color = '#ff9f43';
        restartBtn.style.borderColor = 'rgba(255,159,67,0.5)';
        restartBtn.style.boxShadow = '0 0 15px rgba(255,159,67,0.3)';
      });
      restartBtn.addEventListener('mouseleave', function() {
        restartBtn.style.color = 'rgba(255,255,255,0.6)';
        restartBtn.style.borderColor = 'rgba(255,255,255,0.15)';
        restartBtn.style.boxShadow = 'none';
      });
      restartBtn.addEventListener('click', function() {
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.FrankRestart) {
          window.webkit.messageHandlers.FrankRestart.postMessage('restart');
        }
      });
      overlay.appendChild(restartBtn);

      // Score display (bottom right)
      var scoreBox = document.createElement('div');
      scoreBox.id = 'fk-score';
      scoreBox.style.cssText = 'position:fixed;bottom:24px;right:24px;z-index:99999;'
        + 'background:rgba(0,0,0,0.8);padding:16px 24px;border-radius:20px;'
        + 'font-family:system-ui,sans-serif;text-align:center;pointer-events:none;'
        + 'border:2px solid rgba(0,210,255,0.3);min-width:110px;'
        + 'box-shadow:0 4px 30px rgba(0,210,255,0.2);';

      var scoreLabel = document.createElement('div');
      scoreLabel.style.cssText = 'font-size:10px;color:rgba(255,255,255,0.4);'
        + 'letter-spacing:3px;margin-bottom:4px;';
      scoreLabel.textContent = 'SCORE';
      scoreBox.appendChild(scoreLabel);

      var scoreValue = document.createElement('div');
      scoreValue.id = 'fk-score-value';
      scoreValue.style.cssText = 'font-size:52px;font-weight:800;line-height:1;'
        + 'color:#00d2ff;text-shadow:0 0 20px rgba(0,210,255,0.6);'
        + 'transition:color 0.3s,text-shadow 0.3s;';
      scoreValue.textContent = '0';
      scoreBox.appendChild(scoreValue);

      var scoreFeedback = document.createElement('div');
      scoreFeedback.id = 'fk-feedback';
      scoreFeedback.style.cssText = 'font-size:11px;color:rgba(255,255,255,0.5);'
        + 'margin-top:4px;min-height:14px;transition:color 0.3s;';
      scoreBox.appendChild(scoreFeedback);

      overlay.appendChild(scoreBox);

      // Dual-track pitch canvas (bottom left)
      var pitchCanvas = document.createElement('canvas');
      pitchCanvas.id = 'fk-pitch-canvas';
      pitchCanvas.width = 480;
      pitchCanvas.height = 120;
      pitchCanvas.style.cssText = 'position:fixed;bottom:24px;left:24px;z-index:99999;'
        + 'pointer-events:none;border-radius:16px;'
        + 'background:rgba(0,0,0,0.75);'
        + 'border:1px solid rgba(108,92,231,0.3);'
        + 'box-shadow:0 4px 30px rgba(0,0,0,0.5);';
      overlay.appendChild(pitchCanvas);

      // Note labels on canvas (left edge)
      var noteLabels = document.createElement('div');
      noteLabels.id = 'fk-note-labels';
      noteLabels.style.cssText = 'position:fixed;bottom:24px;left:4px;z-index:100000;'
        + 'height:120px;width:20px;pointer-events:none;'
        + 'display:flex;flex-direction:column;justify-content:space-between;'
        + 'font-family:system-ui,sans-serif;font-size:8px;color:rgba(255,255,255,0.25);'
        + 'padding:4px 0;';
      var notes = ['C6','C5','C4','C3'];
      for (var i = 0; i < notes.length; i++) {
        var nl = document.createElement('div');
        nl.textContent = notes[i];
        noteLabels.appendChild(nl);
      }
      overlay.appendChild(noteLabels);

      document.body.appendChild(overlay);

      // State
      window._fkTrail = [];
      window._fkRefTrail = [];
      window._fkTrailMax = 480;

      // Try to set up Web Audio API on the video element for reference pitch.
      window._fkAudioCtx = null;
      window._fkAnalyser = null;
      window._fkRefPitch = 0;

      function setupAudioAnalyser() {
        var video = document.querySelector('video');
        if (!video) { setTimeout(setupAudioAnalyser, 1000); return; }
        if (window._fkAudioCtx) return;

        try {
          var ctx = new (window.AudioContext || window.webkitAudioContext)();
          var source = ctx.createMediaElementSource(video);
          var analyser = ctx.createAnalyser();
          analyser.fftSize = 2048;
          source.connect(analyser);
          analyser.connect(ctx.destination);
          window._fkAudioCtx = ctx;
          window._fkAnalyser = analyser;
          window._fkBuf = new Float32Array(analyser.fftSize);

          // Run pitch detection loop on the reference audio.
          function detectRefPitch() {
            if (!window._fkAnalyser) return;
            window._fkAnalyser.getFloatTimeDomainData(window._fkBuf);
            window._fkRefPitch = yinPitch(window._fkBuf, ctx.sampleRate);
            requestAnimationFrame(detectRefPitch);
          }
          detectRefPitch();
        } catch(e) {
          // CORS or other restriction — reference pitch won't be available.
        }
      }

      // Simple YIN pitch detection in JS for the reference audio.
      function yinPitch(buf, sr) {
        var size = buf.length;
        var half = Math.floor(size / 2);
        var diff = new Float32Array(half);
        for (var tau = 0; tau < half; tau++) {
          var sum = 0;
          for (var i = 0; i < half; i++) {
            var d = buf[i] - buf[i + tau];
            sum += d * d;
          }
          diff[tau] = sum;
        }
        // CMNDF
        var cmndf = new Float32Array(half);
        cmndf[0] = 1;
        var running = 0;
        for (var tau = 1; tau < half; tau++) {
          running += diff[tau];
          cmndf[tau] = diff[tau] * tau / running;
        }
        // Find first dip below threshold
        var minTau = Math.floor(sr / 900);
        for (var tau = minTau; tau < half; tau++) {
          if (cmndf[tau] < 0.15) {
            while (tau + 1 < half && cmndf[tau + 1] < cmndf[tau]) tau++;
            return sr / tau;
          }
        }
        return 0;
      }

      setupAudioAnalyser();
    })();
  ''';

  static String updateScoreJs(int score) {
    String color, glow, feedback;
    if (score >= 90) {
      color = '#ffd700'; glow = '0 0 30px rgba(255,215,0,0.7)';
      feedback = 'AMAZING!';
    } else if (score >= 75) {
      color = '#00ff88'; glow = '0 0 20px rgba(0,255,136,0.5)';
      feedback = 'Great singing!';
    } else if (score >= 50) {
      color = '#00d2ff'; glow = '0 0 20px rgba(0,210,255,0.4)';
      feedback = 'Keep it up!';
    } else if (score >= 25) {
      color = '#ff9f43'; glow = '0 0 15px rgba(255,159,67,0.4)';
      feedback = 'Getting there...';
    } else {
      color = '#ff6b6b'; glow = '0 0 15px rgba(255,107,107,0.3)';
      feedback = '';
    }
    return '''
      (function() {
        var el = document.getElementById('fk-score-value');
        if (!el) return;
        el.textContent = '$score';
        el.style.color = '$color';
        el.style.textShadow = '$glow';
        var fb = document.getElementById('fk-feedback');
        if (fb) { fb.textContent = '$feedback'; fb.style.color = '$color'; }
      })();
    ''';
  }

  /// Push voice pitch + read reference pitch, draw both on dual-track canvas.
  static String updatePitchTrailJs(double normalizedVoicePitch, double quality) {
    final vp = normalizedVoicePitch.clamp(0.0, 1.0).toStringAsFixed(3);
    final q = quality.clamp(0.0, 1.0).toStringAsFixed(3);
    return '''
      (function() {
        var canvas = document.getElementById('fk-pitch-canvas');
        if (!canvas || !window._fkTrail) return;

        // Get reference pitch (from Web Audio API if available).
        var refHz = window._fkRefPitch || 0;
        var refNorm = refHz > 80 ? Math.min(Math.max((refHz - 80) / 720, 0), 1) : 0;

        window._fkTrail.push({p: $vp, q: $q});
        window._fkRefTrail.push(refNorm);
        if (window._fkTrail.length > window._fkTrailMax) {
          window._fkTrail.shift();
          window._fkRefTrail.shift();
        }

        var trail = window._fkTrail;
        var refTrail = window._fkRefTrail;
        var ctx = canvas.getContext('2d');
        var w = canvas.width, h = canvas.height;
        var pad = 6;
        ctx.clearRect(0, 0, w, h);

        // Note grid lines (C3=130Hz, C4=261Hz, C5=523Hz, C6=1046Hz)
        var noteFreqs = [130.81, 261.63, 523.25, 1046.50];
        var noteNames = ['C3', 'C4', 'C5', 'C6'];
        ctx.font = '9px system-ui';
        for (var n = 0; n < noteFreqs.length; n++) {
          var ny = (noteFreqs[n] - 80) / 720;
          if (ny < 0 || ny > 1) continue;
          var y = h - (ny * (h - 2*pad)) - pad;
          ctx.strokeStyle = 'rgba(255,255,255,0.06)';
          ctx.lineWidth = 1;
          ctx.beginPath(); ctx.moveTo(24, y); ctx.lineTo(w, y); ctx.stroke();
          ctx.fillStyle = 'rgba(255,255,255,0.15)';
          ctx.fillText(noteNames[n], 2, y + 3);
        }

        var startX = w - trail.length;

        // Draw reference pitch trail (song melody — wider, dimmer, purple)
        ctx.globalAlpha = 0.4;
        var prevRx = -1, prevRy = -1;
        for (var i = 0; i < refTrail.length; i++) {
          var rp = refTrail[i];
          if (rp <= 0) { prevRx = -1; continue; }
          var x = startX + i;
          var y = h - (rp * (h - 2*pad)) - pad;
          if (prevRx >= 0 && Math.abs(prevRy - y) < h * 0.4) {
            ctx.strokeStyle = 'rgba(108,92,231,0.7)';
            ctx.lineWidth = 4;
            ctx.beginPath(); ctx.moveTo(prevRx, prevRy); ctx.lineTo(x, y); ctx.stroke();
          }
          prevRx = x; prevRy = y;
        }
        ctx.globalAlpha = 1.0;

        // Draw voice pitch trail (singer — bright, glowing dots)
        var prevVx = -1, prevVy = -1;
        for (var i = 0; i < trail.length; i++) {
          var pt = trail[i];
          if (pt.p <= 0) { prevVx = -1; continue; }
          var x = startX + i;
          var y = h - (pt.p * (h - 2*pad)) - pad;

          // Color by match quality
          var r = Math.round(255 * (1 - pt.q));
          var g = Math.round(220 * pt.q + 35);
          var col = 'rgb(' + r + ',' + g + ',80)';

          // Connecting line
          if (prevVx >= 0 && Math.abs(prevVy - y) < h * 0.4) {
            ctx.strokeStyle = col;
            ctx.lineWidth = 2;
            ctx.globalAlpha = 0.5;
            ctx.beginPath(); ctx.moveTo(prevVx, prevVy); ctx.lineTo(x, y); ctx.stroke();
            ctx.globalAlpha = 1.0;
          }

          // Glowing dot
          ctx.shadowColor = col;
          ctx.shadowBlur = pt.q > 0.5 ? 10 : 4;
          ctx.fillStyle = col;
          ctx.beginPath();
          ctx.arc(x, y, pt.q > 0.5 ? 3.5 : 2, 0, 6.283);
          ctx.fill();
          ctx.shadowBlur = 0;

          prevVx = x; prevVy = y;
        }

        // Legend (bottom right of canvas)
        ctx.globalAlpha = 0.5;
        ctx.fillStyle = '#6c5ce7'; ctx.fillRect(w-90, h-14, 12, 3);
        ctx.fillStyle = '#fff'; ctx.font = '8px system-ui';
        ctx.fillText('Song', w-74, h-11);
        ctx.fillStyle = '#00ff88'; ctx.fillRect(w-45, h-14, 12, 3);
        ctx.fillText('You', w-29, h-11);
        ctx.globalAlpha = 1.0;
      })();
    ''';
  }

  /// Update the note label and mic activity dot.
  static String updateNoteAndRmsJs(String noteName, double normalizedRms) {
    final pct = (normalizedRms * 100).clamp(0, 100).toStringAsFixed(0);
    return '''
      (function() {
        var nl = document.getElementById('fk-note-label');
        if (nl) nl.textContent = '$noteName';
        var dot = document.getElementById('fk-mic-dot');
        if (!dot) return;
        var n = $pct / 100;
        if (n > 0.05) {
          var sz = 10 + n * 8;
          dot.style.width = sz + 'px';
          dot.style.height = sz + 'px';
          dot.style.background = 'rgb(0,' + Math.round(180 + n*75) + ',255)';
          dot.style.boxShadow = '0 0 ' + Math.round(n*25) + 'px rgba(0,210,255,' + (n*0.8).toFixed(2) + ')';
        } else {
          dot.style.width = '10px'; dot.style.height = '10px';
          dot.style.background = '#333'; dot.style.boxShadow = 'none';
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

  /// End-of-song celebration screen with fireworks and final score.
  static String celebrationJs(int score) {
    String phrase, emoji;
    if (score >= 90) {
      phrase = 'SUPERSTAR!'; emoji = '🌟';
    } else if (score >= 75) {
      phrase = 'Well Done!'; emoji = '🎉';
    } else if (score >= 50) {
      phrase = 'Nice Try!'; emoji = '👏';
    } else if (score >= 25) {
      phrase = 'Almost There!'; emoji = '💪';
    } else {
      phrase = 'Keep Practicing!'; emoji = '🎤';
    }
    return '''
      (function() {
        // Remove existing celebration
        var old = document.getElementById('fk-celebration');
        if (old) old.remove();

        var c = document.createElement('div');
        c.id = 'fk-celebration';
        c.style.cssText = 'position:fixed;inset:0;z-index:999999;'
          + 'background:rgba(0,0,0,0.85);display:flex;flex-direction:column;'
          + 'align-items:center;justify-content:center;pointer-events:none;'
          + 'animation:fkFadeIn 0.5s ease-out;font-family:system-ui,sans-serif;';

        // Emoji burst
        var emojiBurst = document.createElement('div');
        emojiBurst.style.cssText = 'font-size:80px;margin-bottom:16px;'
          + 'animation:fkBounce 0.6s ease-out;';
        emojiBurst.textContent = '$emoji';
        c.appendChild(emojiBurst);

        // Phrase
        var phraseEl = document.createElement('div');
        phraseEl.style.cssText = 'font-size:48px;font-weight:800;color:#fff;'
          + 'margin-bottom:8px;text-shadow:0 0 30px rgba(255,215,0,0.6);'
          + 'animation:fkSlideUp 0.5s ease-out 0.2s both;';
        phraseEl.textContent = '$phrase';
        c.appendChild(phraseEl);

        // Final score
        var scoreEl = document.createElement('div');
        scoreEl.style.cssText = 'font-size:96px;font-weight:900;line-height:1;'
          + 'margin:16px 0;animation:fkSlideUp 0.5s ease-out 0.4s both;';
        if ($score >= 75) {
          scoreEl.style.color = '#ffd700';
          scoreEl.style.textShadow = '0 0 40px rgba(255,215,0,0.8),0 0 80px rgba(255,215,0,0.4)';
        } else if ($score >= 50) {
          scoreEl.style.color = '#00ff88';
          scoreEl.style.textShadow = '0 0 30px rgba(0,255,136,0.6)';
        } else {
          scoreEl.style.color = '#00d2ff';
          scoreEl.style.textShadow = '0 0 20px rgba(0,210,255,0.5)';
        }
        scoreEl.textContent = '$score';
        c.appendChild(scoreEl);

        // "points" label
        var ptsEl = document.createElement('div');
        ptsEl.style.cssText = 'font-size:18px;color:rgba(255,255,255,0.5);'
          + 'letter-spacing:6px;animation:fkSlideUp 0.5s ease-out 0.5s both;';
        ptsEl.textContent = 'POINTS';
        c.appendChild(ptsEl);

        // Particle fireworks (CSS-only sparkles)
        for (var i = 0; i < 30; i++) {
          var p = document.createElement('div');
          var x = Math.random() * 100;
          var y = Math.random() * 100;
          var size = 3 + Math.random() * 5;
          var delay = Math.random() * 1.5;
          var colors = ['#ffd700','#ff6b6b','#00d2ff','#00ff88','#ff9f43','#6c5ce7'];
          var col = colors[Math.floor(Math.random() * colors.length)];
          p.style.cssText = 'position:absolute;left:' + x + '%;top:' + y + '%;'
            + 'width:' + size + 'px;height:' + size + 'px;border-radius:50%;'
            + 'background:' + col + ';pointer-events:none;'
            + 'animation:fkSparkle 1.5s ease-out ' + delay.toFixed(2) + 's both;'
            + 'box-shadow:0 0 ' + (size*3) + 'px ' + col + ';';
          c.appendChild(p);
        }

        // Inject keyframe animations via a style element
        var style = document.createElement('style');
        style.textContent = [
          '@keyframes fkFadeIn{from{opacity:0}to{opacity:1}}',
          '@keyframes fkBounce{0%{transform:scale(0)}50%{transform:scale(1.3)}100%{transform:scale(1)}}',
          '@keyframes fkSlideUp{from{opacity:0;transform:translateY(30px)}to{opacity:1;transform:translateY(0)}}',
          '@keyframes fkSparkle{0%{opacity:1;transform:scale(1)}100%{opacity:0;transform:scale(0) translateY(-50px)}}'
        ].join('');
        c.appendChild(style);

        document.body.appendChild(c);

        // Auto-remove after 6 seconds
        setTimeout(function() {
          if (c.parentNode) c.style.animation = 'fkFadeIn 0.5s ease-out reverse';
          setTimeout(function() { if (c.parentNode) c.remove(); }, 500);
        }, 6000);
      })();
    ''';
  }

  static const removeOverlayJs = '''
    (function() {
      var el = document.getElementById('fk-overlay');
      if (el) el.remove();
      if (window._fkAudioCtx) { window._fkAudioCtx.close(); }
      delete window._fkTrail; delete window._fkRefTrail;
      delete window._fkTrailMax; delete window._fkAudioCtx;
      delete window._fkAnalyser; delete window._fkBuf;
      delete window._fkRefPitch;
    })();
  ''';
}
