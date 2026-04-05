/// JavaScript overlay injected into the YouTube webview.
/// Uses DOM createElement for YouTube's Trusted Types CSP.
class WebviewOverlay {
  /// Welcome screen shown on first launch.
  static const welcomeOverlayJs = '''
    (function() {
      if (document.getElementById('fk-welcome')) return;

      var bg = document.createElement('div');
      bg.id = 'fk-welcome';
      bg.style.cssText = 'position:fixed;inset:0;z-index:999999;'
        + 'background:rgba(0,0,0,0.88);display:flex;align-items:center;'
        + 'justify-content:center;font-family:system-ui,sans-serif;'
        + 'animation:fkFadeIn 0.4s ease-out;';

      var card = document.createElement('div');
      card.style.cssText = 'max-width:540px;background:rgba(20,20,40,0.95);'
        + 'border-radius:24px;padding:36px 40px;color:#fff;'
        + 'border:1px solid rgba(108,92,231,0.4);'
        + 'box-shadow:0 8px 60px rgba(108,92,231,0.3);';

      var title = document.createElement('div');
      title.style.cssText = 'font-size:32px;font-weight:800;margin-bottom:8px;'
        + 'background:linear-gradient(135deg,#6c5ce7,#00d2ff);'
        + '-webkit-background-clip:text;-webkit-text-fill-color:transparent;';
      title.textContent = 'Frank Karaoke';
      card.appendChild(title);

      var sub = document.createElement('div');
      sub.style.cssText = 'font-size:15px;color:rgba(255,255,255,0.5);margin-bottom:24px;';
      sub.textContent = 'Sing along with any YouTube karaoke video';
      card.appendChild(sub);

      var sections = [
        {
          icon: '\\u{1F3B5}',
          title: 'How it works',
          text: 'Play any YouTube karaoke video and sing along. '
            + 'The app listens to the music and your voice separately, '
            + 'then scores how well they match in real-time.'
        },
        {
          icon: '\\u{1F3AF}',
          title: 'Pick your scoring style',
          text: 'Pitch \\u2014 are you hitting the right notes? '
            + 'Contour \\u2014 are you following the melody shape? '
            + 'Interval \\u2014 are your note jumps right? '
            + 'Streak \\u2014 party mode with combo multipliers!'
        },
        {
          icon: '\\u{1F527}',
          title: 'Settings (gear icon, top-left)',
          text: 'Mic preset, scoring mode, pitch shift, and mic calibration. '
            + 'Calibrate first! It listens to your room for 3 seconds to set '
            + 'the right noise level.'
        }
      ];

      for (var i = 0; i < sections.length; i++) {
        var s = sections[i];
        var row = document.createElement('div');
        row.style.cssText = 'display:flex;gap:14px;margin-bottom:18px;align-items:flex-start;';
        var icon = document.createElement('div');
        icon.style.cssText = 'font-size:24px;flex-shrink:0;margin-top:1px;';
        icon.textContent = s.icon;
        row.appendChild(icon);
        var col = document.createElement('div');
        var t = document.createElement('div');
        t.style.cssText = 'font-size:15px;font-weight:700;color:#fff;margin-bottom:3px;';
        t.textContent = s.title;
        col.appendChild(t);
        var p = document.createElement('div');
        p.style.cssText = 'font-size:13px;color:rgba(255,255,255,0.55);line-height:1.5;';
        p.textContent = s.text;
        col.appendChild(p);
        row.appendChild(col);
        card.appendChild(row);
      }

      // Calibration callout
      var calTip = document.createElement('div');
      calTip.style.cssText = 'background:rgba(0,210,255,0.1);border:1px solid rgba(0,210,255,0.25);'
        + 'border-radius:12px;padding:10px 14px;margin-bottom:4px;'
        + 'font-size:12px;color:rgba(0,210,255,0.85);line-height:1.4;';
      calTip.textContent = '\\u{1F4A1} Tip: Open settings and calibrate your mic before singing. '
        + 'It takes 3 seconds and makes scoring work in any room.';
      card.appendChild(calTip);

      var btnRow = document.createElement('div');
      btnRow.style.cssText = 'display:flex;gap:10px;margin-top:16px;justify-content:flex-end;';

      var dontShow = document.createElement('div');
      dontShow.textContent = "Don\\u0027t show again";
      dontShow.style.cssText = 'padding:10px 18px;border-radius:12px;'
        + 'background:transparent;color:rgba(255,255,255,0.4);'
        + 'font-size:12px;cursor:pointer;user-select:none;-webkit-user-select:none;'
        + 'transition:color 0.2s;display:flex;align-items:center;';
      dontShow.addEventListener('mouseenter', function() { dontShow.style.color = '#fff'; });
      dontShow.addEventListener('mouseleave', function() { dontShow.style.color = 'rgba(255,255,255,0.4)'; });
      dontShow.addEventListener('click', function(e) {
        e.stopPropagation(); e.preventDefault();
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.FrankDismissWelcome) {
          window.webkit.messageHandlers.FrankDismissWelcome.postMessage('permanent');
        }
        bg.style.animation = 'fkFadeIn 0.3s ease-out reverse';
        setTimeout(function() { if (bg.parentNode) bg.remove(); }, 300);
      }, true);
      dontShow.addEventListener('mousedown', function(e){ e.stopPropagation(); }, true);
      btnRow.appendChild(dontShow);

      var closeBtn = document.createElement('div');
      closeBtn.textContent = 'Got it!';
      closeBtn.style.cssText = 'padding:10px 24px;border-radius:12px;'
        + 'background:linear-gradient(135deg,#6c5ce7,#00d2ff);color:#fff;'
        + 'font-size:13px;font-weight:700;cursor:pointer;'
        + 'user-select:none;-webkit-user-select:none;'
        + 'box-shadow:0 4px 20px rgba(108,92,231,0.4);transition:transform 0.2s;';
      closeBtn.addEventListener('mouseenter', function() { closeBtn.style.transform = 'scale(1.05)'; });
      closeBtn.addEventListener('mouseleave', function() { closeBtn.style.transform = 'scale(1)'; });
      closeBtn.addEventListener('click', function(e) {
        e.stopPropagation(); e.preventDefault();
        bg.style.animation = 'fkFadeIn 0.3s ease-out reverse';
        setTimeout(function() { if (bg.parentNode) bg.remove(); }, 300);
      }, true);
      closeBtn.addEventListener('mousedown', function(e){ e.stopPropagation(); }, true);
      btnRow.appendChild(closeBtn);

      card.appendChild(btnRow);
      bg.appendChild(card);

      var style = document.createElement('style');
      style.textContent = '@keyframes fkFadeIn{from{opacity:0}to{opacity:1}}';
      bg.appendChild(style);

      document.body.appendChild(bg);
    })();
  ''';
  /// Full overlay with scoring + toggleable controls panel.
  static String injectOverlayJs({
    required String singerName,
    required String activePreset,
    required String activeScoringMode,
    required int pitchShift,
  }) => '''
    (function() {
      var existing = document.getElementById('fk-overlay');
      if (existing) existing.remove();

      var overlay = document.createElement('div');
      overlay.id = 'fk-overlay';

      // --- Gear button (top left, toggles settings panel) ---
      var gearBtn = document.createElement('div');
      gearBtn.id = 'fk-gear';
      gearBtn.textContent = '\\u2699';
      gearBtn.style.cssText = 'position:fixed;top:14px;left:14px;z-index:100001;'
        + 'width:40px;height:40px;border-radius:50%;'
        + 'background:rgba(0,0,0,0.7);color:rgba(255,255,255,0.6);'
        + 'font-size:22px;display:flex;align-items:center;justify-content:center;'
        + 'cursor:pointer;pointer-events:auto;'
        + 'border:1px solid rgba(255,255,255,0.2);transition:all 0.2s ease;'
        + 'user-select:none;-webkit-user-select:none;';
      gearBtn.addEventListener('mouseenter', function() {
        gearBtn.style.color = '#00d2ff';
        gearBtn.style.borderColor = 'rgba(0,210,255,0.5)';
      });
      gearBtn.addEventListener('mouseleave', function() {
        var panel = document.getElementById('fk-controls');
        var isOpen = panel && panel.style.display !== 'none';
        if (!isOpen) {
          gearBtn.style.color = 'rgba(255,255,255,0.6)';
          gearBtn.style.borderColor = 'rgba(255,255,255,0.2)';
        }
      });
      gearBtn.addEventListener('click', function(e) {
        e.stopPropagation(); e.preventDefault();
        var panel = document.getElementById('fk-controls');
        if (!panel) return;
        var isOpen = panel.style.display !== 'none';
        panel.style.display = isOpen ? 'none' : 'block';
        gearBtn.style.color = isOpen ? 'rgba(255,255,255,0.6)' : '#00d2ff';
        gearBtn.style.borderColor = isOpen ? 'rgba(255,255,255,0.2)' : 'rgba(0,210,255,0.5)';
      }, true);
      gearBtn.addEventListener('mousedown', function(e){ e.stopPropagation(); }, true);
      overlay.appendChild(gearBtn);

      // --- Score box (bottom right) with note display on top ---
      var scoreContainer = document.createElement('div');
      scoreContainer.style.cssText = 'position:fixed;bottom:24px;right:24px;z-index:99999;'
        + 'pointer-events:none;display:flex;flex-direction:column;align-items:center;gap:8px;';

      // Note display (on top of score)
      var noteBox = document.createElement('div');
      noteBox.id = 'fk-note-box';
      noteBox.style.cssText = 'background:rgba(0,0,0,0.75);padding:6px 14px;border-radius:14px;'
        + 'font-family:system-ui,sans-serif;display:flex;'
        + 'align-items:center;gap:8px;border:1px solid rgba(0,210,255,0.3);';
      var micDot = document.createElement('div');
      micDot.id = 'fk-mic-dot';
      micDot.style.cssText = 'width:10px;height:10px;border-radius:50%;'
        + 'background:#333;transition:all 0.1s ease-out;flex-shrink:0;';
      noteBox.appendChild(micDot);
      var noteLabel = document.createElement('div');
      noteLabel.id = 'fk-note-label';
      noteLabel.style.cssText = 'color:#00d2ff;font-size:20px;font-weight:700;'
        + 'min-width:42px;text-align:center;text-shadow:0 0 10px rgba(0,210,255,0.5);';
      noteLabel.textContent = '--';
      noteBox.appendChild(noteLabel);
      scoreContainer.appendChild(noteBox);

      // Score display
      var scoreBox = document.createElement('div');
      scoreBox.id = 'fk-score';
      scoreBox.style.cssText = 'background:rgba(0,0,0,0.8);padding:14px 22px;border-radius:20px;'
        + 'font-family:system-ui,sans-serif;text-align:center;'
        + 'border:2px solid rgba(0,210,255,0.3);min-width:110px;'
        + 'box-shadow:0 4px 30px rgba(0,210,255,0.2);';
      var scoreLabel = document.createElement('div');
      scoreLabel.style.cssText = 'font-size:10px;color:rgba(255,255,255,0.4);letter-spacing:3px;margin-bottom:4px;';
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

      // Overall score row
      var overallRow = document.createElement('div');
      overallRow.style.cssText = 'margin-top:8px;padding-top:8px;'
        + 'border-top:1px solid rgba(255,255,255,0.1);'
        + 'display:flex;align-items:baseline;justify-content:center;gap:6px;';
      var overallLabel = document.createElement('div');
      overallLabel.style.cssText = 'font-size:9px;color:rgba(255,255,255,0.3);letter-spacing:2px;';
      overallLabel.textContent = 'OVERALL';
      overallRow.appendChild(overallLabel);
      var overallValue = document.createElement('div');
      overallValue.id = 'fk-overall-value';
      overallValue.style.cssText = 'font-size:20px;font-weight:700;'
        + 'color:rgba(255,255,255,0.5);transition:color 0.5s;';
      overallValue.textContent = '0';
      overallRow.appendChild(overallValue);
      scoreBox.appendChild(overallRow);

      scoreContainer.appendChild(scoreBox);
      overlay.appendChild(scoreContainer);

      // --- Song title (bottom right, below score) ---
      var singer = document.createElement('div');
      singer.id = 'fk-singer';
      singer.textContent = '$singerName';
      singer.style.cssText = 'position:fixed;bottom:24px;right:170px;z-index:99999;'
        + 'background:linear-gradient(135deg,rgba(108,92,231,0.85),rgba(0,0,0,0.7));'
        + 'color:#fff;padding:8px 16px;border-radius:20px;'
        + 'font-family:system-ui,sans-serif;font-size:12px;font-weight:600;'
        + 'pointer-events:none;max-width:35%;'
        + 'overflow:hidden;text-overflow:ellipsis;white-space:nowrap;'
        + 'box-shadow:0 2px 16px rgba(108,92,231,0.3);';
      overlay.appendChild(singer);

      // --- Pitch canvas (bottom left) ---
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

      // --- Settings panel (right side, hidden by default) ---
      var panel = document.createElement('div');
      panel.id = 'fk-controls';
      panel.style.cssText = 'position:fixed;top:14px;left:60px;z-index:100000;'
        + 'width:280px;background:rgba(0,0,0,0.9);border-radius:16px;'
        + 'padding:16px;font-family:system-ui,sans-serif;color:#fff;'
        + 'pointer-events:auto;border:1px solid rgba(108,92,231,0.4);'
        + 'box-shadow:0 8px 40px rgba(0,0,0,0.7);display:none;';

      // Preset section
      var presetLabel = document.createElement('div');
      presetLabel.style.cssText = 'font-size:10px;color:rgba(255,255,255,0.4);'
        + 'letter-spacing:2px;margin-bottom:8px;';
      presetLabel.textContent = 'MIC PRESET';
      panel.appendChild(presetLabel);

      var presetRow = document.createElement('div');
      presetRow.id = 'fk-preset-row';
      presetRow.style.cssText = 'display:flex;gap:6px;margin-bottom:16px;';

      var presets = [
        {id:'externalMic', label:'\\u{1F3A4} Clean'},
        {id:'roomMic', label:'\\u{1F3E0} Room'},
        {id:'partyMode', label:'\\u{1F389} Party'}
      ];
      for (var i = 0; i < presets.length; i++) {
        var p = presets[i];
        var btn = document.createElement('div');
        btn.id = 'fk-preset-' + p.id;
        btn.setAttribute('data-preset', p.id);
        btn.textContent = p.label;
        var isActive = p.id === '$activePreset';
        btn.style.cssText = 'flex:1;padding:8px 4px;border-radius:10px;'
          + 'text-align:center;cursor:pointer;font-size:12px;font-weight:600;'
          + 'transition:all 0.2s ease;user-select:none;-webkit-user-select:none;'
          + (isActive
            ? 'background:rgba(108,92,231,0.6);border:1px solid rgba(108,92,231,0.8);color:#fff;'
            : 'background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.1);color:rgba(255,255,255,0.6);');
        btn.addEventListener('click', (function(pid) {
          return function(e) {
            e.stopPropagation(); e.preventDefault();
            if (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.FrankPreset) {
              window.webkit.messageHandlers.FrankPreset.postMessage(pid);
            }
          };
        })(p.id), true);
        btn.addEventListener('mousedown', function(e){ e.stopPropagation(); }, true);
        presetRow.appendChild(btn);
      }
      panel.appendChild(presetRow);

      // Pitch shift section
      var pitchLabel = document.createElement('div');
      pitchLabel.style.cssText = 'font-size:10px;color:rgba(255,255,255,0.4);'
        + 'letter-spacing:2px;margin-bottom:8px;display:flex;'
        + 'justify-content:space-between;align-items:center;';
      pitchLabel.textContent = 'PITCH SHIFT';
      var pitchValueLabel = document.createElement('span');
      pitchValueLabel.id = 'fk-pitch-value';
      pitchValueLabel.style.cssText = 'color:#00d2ff;font-size:14px;font-weight:700;letter-spacing:0;';
      pitchValueLabel.textContent = ($pitchShift > 0 ? '+' : '') + '$pitchShift';
      pitchLabel.appendChild(pitchValueLabel);
      panel.appendChild(pitchLabel);

      var pitchRow = document.createElement('div');
      pitchRow.style.cssText = 'display:flex;align-items:center;gap:8px;margin-bottom:16px;';

      function mkPitchBtn(label, dir) {
        var b = document.createElement('div');
        b.textContent = label;
        b.style.cssText = 'width:32px;height:32px;border-radius:50%;'
          + 'background:rgba(255,255,255,0.1);color:#fff;font-size:18px;'
          + 'display:flex;align-items:center;justify-content:center;cursor:pointer;'
          + 'user-select:none;-webkit-user-select:none;transition:background 0.2s;';
        b.addEventListener('click', function(e) {
          e.stopPropagation(); e.preventDefault();
          if (window.webkit && window.webkit.messageHandlers &&
              window.webkit.messageHandlers.FrankPitch) {
            window.webkit.messageHandlers.FrankPitch.postMessage(dir);
          }
        }, true);
        b.addEventListener('mousedown', function(e){ e.stopPropagation(); }, true);
        return b;
      }
      pitchRow.appendChild(mkPitchBtn('\\u2212', 'down'));

      var pitchBar = document.createElement('div');
      pitchBar.style.cssText = 'flex:1;height:6px;background:rgba(255,255,255,0.1);'
        + 'border-radius:3px;position:relative;';
      var pitchFill = document.createElement('div');
      pitchFill.id = 'fk-pitch-fill';
      var fillPct = (($pitchShift + 6) / 12 * 100);
      pitchFill.style.cssText = 'position:absolute;left:0;top:0;height:100%;'
        + 'width:' + fillPct + '%;background:linear-gradient(90deg,#6c5ce7,#00d2ff);'
        + 'border-radius:3px;transition:width 0.2s;';
      pitchBar.appendChild(pitchFill);
      var centerMark = document.createElement('div');
      centerMark.style.cssText = 'position:absolute;left:50%;top:-4px;'
        + 'width:2px;height:14px;background:rgba(255,255,255,0.2);transform:translateX(-50%);';
      pitchBar.appendChild(centerMark);
      pitchRow.appendChild(pitchBar);
      pitchRow.appendChild(mkPitchBtn('+', 'up'));
      panel.appendChild(pitchRow);

      // Scoring mode section
      var modeLabel = document.createElement('div');
      modeLabel.style.cssText = 'font-size:10px;color:rgba(255,255,255,0.4);'
        + 'letter-spacing:2px;margin-bottom:8px;';
      modeLabel.textContent = 'SCORING MODE';
      panel.appendChild(modeLabel);

      var modeRow = document.createElement('div');
      modeRow.id = 'fk-mode-row';
      modeRow.style.cssText = 'display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-bottom:16px;';

      var modes = [
        {id:'pitchClass', label:'\\u{1F3AF} Pitch', desc:'Best for songs you know well'},
        {id:'contour', label:'\\u{3030} Contour', desc:'Best for learning new songs'},
        {id:'interval', label:'\\u{1F4D0} Interval', desc:'Best when singing in another key'},
        {id:'streak', label:'\\u{1F525} Streak', desc:'Best for parties and competition'}
      ];
      for (var i = 0; i < modes.length; i++) {
        var m = modes[i];
        var btn = document.createElement('div');
        btn.id = 'fk-mode-' + m.id;
        var isActive = m.id === '$activeScoringMode';
        btn.style.cssText = 'padding:6px 6px;border-radius:8px;'
          + 'cursor:pointer;transition:all 0.2s;user-select:none;-webkit-user-select:none;'
          + (isActive
            ? 'background:rgba(0,210,255,0.3);border:1px solid rgba(0,210,255,0.6);'
            : 'background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.08);');
        var btnLabel = document.createElement('div');
        btnLabel.style.cssText = 'font-size:11px;font-weight:600;'
          + (isActive ? 'color:#00d2ff;' : 'color:rgba(255,255,255,0.5);');
        btnLabel.textContent = m.label;
        btn.appendChild(btnLabel);
        var btnDesc = document.createElement('div');
        btnDesc.style.cssText = 'font-size:8px;margin-top:2px;line-height:1.2;'
          + (isActive ? 'color:rgba(0,210,255,0.6);' : 'color:rgba(255,255,255,0.25);');
        btnDesc.textContent = m.desc;
        btn.appendChild(btnDesc);
        btn.addEventListener('click', (function(mid) {
          return function(e) {
            e.stopPropagation(); e.preventDefault();
            if (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.FrankMode) {
              window.webkit.messageHandlers.FrankMode.postMessage(mid);
            }
          };
        })(m.id), true);
        btn.addEventListener('mousedown', function(e){ e.stopPropagation(); }, true);
        modeRow.appendChild(btn);
      }
      panel.appendChild(modeRow);

      // Restart button
      var restartBtn = document.createElement('div');
      restartBtn.textContent = '\\u21BB  Restart Song';
      restartBtn.style.cssText = 'padding:10px;border-radius:10px;'
        + 'background:rgba(255,159,67,0.15);border:1px solid rgba(255,159,67,0.3);'
        + 'color:#ff9f43;font-size:13px;font-weight:600;text-align:center;'
        + 'cursor:pointer;user-select:none;-webkit-user-select:none;transition:all 0.2s;';
      restartBtn.addEventListener('mouseenter', function() {
        restartBtn.style.background = 'rgba(255,159,67,0.3)';
      });
      restartBtn.addEventListener('mouseleave', function() {
        restartBtn.style.background = 'rgba(255,159,67,0.15)';
      });
      restartBtn.addEventListener('click', function(e) {
        e.stopPropagation(); e.preventDefault();
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.FrankRestart) {
          window.webkit.messageHandlers.FrankRestart.postMessage('restart');
        }
      }, true);
      restartBtn.addEventListener('mousedown', function(e){ e.stopPropagation(); }, true);
      panel.appendChild(restartBtn);

      // Calibrate mic button
      var calBtn = document.createElement('div');
      calBtn.id = 'fk-calibrate-btn';
      calBtn.textContent = '\\u{1F399} Calibrate Mic';
      calBtn.style.cssText = 'padding:10px;border-radius:10px;margin-top:8px;'
        + 'background:rgba(0,210,255,0.1);border:1px solid rgba(0,210,255,0.25);'
        + 'color:rgba(0,210,255,0.8);font-size:13px;font-weight:600;text-align:center;'
        + 'cursor:pointer;user-select:none;-webkit-user-select:none;transition:all 0.2s;';
      calBtn.addEventListener('mouseenter', function() {
        calBtn.style.background = 'rgba(0,210,255,0.2)';
      });
      calBtn.addEventListener('mouseleave', function() {
        if (!window._fkCalibrating) calBtn.style.background = 'rgba(0,210,255,0.1)';
      });
      calBtn.addEventListener('click', function(e) {
        e.stopPropagation(); e.preventDefault();
        if (window._fkCalibrating) return;
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.FrankCalibrate) {
          window.webkit.messageHandlers.FrankCalibrate.postMessage('start');
        }
      }, true);
      calBtn.addEventListener('mousedown', function(e){ e.stopPropagation(); }, true);
      panel.appendChild(calBtn);

      overlay.appendChild(panel);
      document.body.appendChild(overlay);

      window._fkTrail = [];
      window._fkTrailMax = 480;
    })();
  ''';

  static String updatePresetJs(String presetId) => '''
    (function() {
      var ids = ['externalMic','roomMic','partyMode'];
      for (var i = 0; i < ids.length; i++) {
        var btn = document.getElementById('fk-preset-' + ids[i]);
        if (!btn) continue;
        if (ids[i] === '$presetId') {
          btn.style.background = 'rgba(108,92,231,0.6)';
          btn.style.borderColor = 'rgba(108,92,231,0.8)';
          btn.style.color = '#fff';
        } else {
          btn.style.background = 'rgba(255,255,255,0.08)';
          btn.style.borderColor = 'rgba(255,255,255,0.1)';
          btn.style.color = 'rgba(255,255,255,0.6)';
        }
      }
    })();
  ''';

  static String updateModeJs(String modeId) => '''
    (function() {
      var ids = ['pitchClass','contour','interval','streak'];
      for (var i = 0; i < ids.length; i++) {
        var btn = document.getElementById('fk-mode-' + ids[i]);
        if (!btn) continue;
        if (ids[i] === '$modeId') {
          btn.style.background = 'rgba(0,210,255,0.3)';
          btn.style.borderColor = 'rgba(0,210,255,0.6)';
          btn.style.color = '#00d2ff';
        } else {
          btn.style.background = 'rgba(255,255,255,0.06)';
          btn.style.borderColor = 'rgba(255,255,255,0.08)';
          btn.style.color = 'rgba(255,255,255,0.5)';
        }
      }
    })();
  ''';

  /// Update calibration button state.
  static String updateCalibrateJs(String text, {bool active = false}) => '''
    (function() {
      var btn = document.getElementById('fk-calibrate-btn');
      if (!btn) return;
      btn.textContent = '$text';
      window._fkCalibrating = $active;
      btn.style.background = $active
        ? 'rgba(0,210,255,0.3)'
        : 'rgba(0,210,255,0.1)';
      btn.style.cursor = $active ? 'wait' : 'pointer';
    })();
  ''';

  static String updatePitchShiftJs(int semitones) {
    final label = (semitones > 0 ? '+' : '') + semitones.toString();
    final fillPct = ((semitones + 6) / 12 * 100).clamp(0, 100).toStringAsFixed(1);
    return '''
      (function() {
        var lbl = document.getElementById('fk-pitch-value');
        if (lbl) lbl.textContent = '$label';
        var fill = document.getElementById('fk-pitch-fill');
        if (fill) fill.style.width = '$fillPct%';
      })();
    ''';
  }

  static String updateScoreJs(int liveScore, int overallScore,
      {int streakCount = 0}) {
    String color, glow, feedback;
    if (streakCount > 20) {
      color = '#ffd700'; glow = '0 0 30px rgba(255,215,0,0.7)';
      feedback = '\u{1F525} ${streakCount}x COMBO!';
    } else if (streakCount > 10) {
      color = '#ff9f43'; glow = '0 0 20px rgba(255,159,67,0.5)';
      feedback = '\u{1F525} ${streakCount}x streak';
    } else if (liveScore >= 90) {
      color = '#ffd700'; glow = '0 0 30px rgba(255,215,0,0.7)'; feedback = 'AMAZING!';
    } else if (liveScore >= 75) {
      color = '#00ff88'; glow = '0 0 20px rgba(0,255,136,0.5)'; feedback = 'Great singing!';
    } else if (liveScore >= 50) {
      color = '#00d2ff'; glow = '0 0 20px rgba(0,210,255,0.4)'; feedback = 'Keep it up!';
    } else if (liveScore >= 25) {
      color = '#ff9f43'; glow = '0 0 15px rgba(255,159,67,0.4)'; feedback = 'Getting there...';
    } else {
      color = '#ff6b6b'; glow = '0 0 15px rgba(255,107,107,0.3)';
      feedback = streakCount == 0 && liveScore < 15 ? 'Streak broken!' : '';
    }
    String oColor;
    if (overallScore >= 75) { oColor = 'rgba(0,255,136,0.7)'; }
    else if (overallScore >= 50) { oColor = 'rgba(0,210,255,0.7)'; }
    else { oColor = 'rgba(255,255,255,0.5)'; }
    return '''
      (function() {
        var el = document.getElementById('fk-score-value');
        if (!el) return;
        el.textContent = '$liveScore';
        el.style.color = '$color';
        el.style.textShadow = '$glow';
        var fb = document.getElementById('fk-feedback');
        if (fb) { fb.textContent = '$feedback'; fb.style.color = '$color'; }
        var ov = document.getElementById('fk-overall-value');
        if (ov) { ov.textContent = '$overallScore'; ov.style.color = '$oColor'; }
      })();
    ''';
  }

  static String updatePitchTrailJs(double normalizedVoicePitch, double quality) {
    final vp = normalizedVoicePitch.clamp(0.0, 1.0).toStringAsFixed(3);
    final q = quality.clamp(0.0, 1.0).toStringAsFixed(3);
    return '''
      (function() {
        var canvas = document.getElementById('fk-pitch-canvas');
        if (!canvas || !window._fkTrail) return;
        window._fkTrail.push({p:$vp, q:$q});
        if (window._fkTrail.length > window._fkTrailMax) window._fkTrail.shift();
        var trail=window._fkTrail;
        var ctx=canvas.getContext('2d'), w=canvas.width, h=canvas.height, pad=6;
        ctx.clearRect(0,0,w,h);
        var nf=[130.81,196,261.63,392,523.25,783.99], nn=['C3','G3','C4','G4','C5','G5'];
        var logMin=Math.log(100), logRange=Math.log(800)-logMin;
        ctx.font='9px system-ui';
        for(var n=0;n<nf.length;n++){
          var ny=(Math.log(nf[n])-logMin)/logRange; if(ny<0||ny>1)continue;
          var y=h-(ny*(h-2*pad))-pad;
          ctx.strokeStyle='rgba(255,255,255,0.06)'; ctx.lineWidth=1;
          ctx.beginPath();ctx.moveTo(24,y);ctx.lineTo(w,y);ctx.stroke();
          ctx.fillStyle='rgba(255,255,255,0.2)';ctx.fillText(nn[n],2,y+3);
        }
        var sx=w-trail.length, pvx=-1,pvy=-1;
        for(var i=0;i<trail.length;i++){
          var pt=trail[i]; if(pt.p<=0){pvx=-1;continue;}
          var x=sx+i, y=h-(pt.p*(h-2*pad))-pad;
          var r=Math.round(255*(1-pt.q)),g=Math.round(220*pt.q+35);
          var col='rgb('+r+','+g+',80)';
          if(pvx>=0&&Math.abs(pvy-y)<h*0.4){
            ctx.strokeStyle=col;ctx.lineWidth=2;ctx.globalAlpha=0.5;
            ctx.beginPath();ctx.moveTo(pvx,pvy);ctx.lineTo(x,y);ctx.stroke();
            ctx.globalAlpha=1.0;
          }
          ctx.shadowColor=col;ctx.shadowBlur=pt.q>0.5?10:4;
          ctx.fillStyle=col;ctx.beginPath();
          ctx.arc(x,y,pt.q>0.5?3.5:2,0,6.283);ctx.fill();ctx.shadowBlur=0;
          pvx=x;pvy=y;
        }
      })();
    ''';
  }

  static String updateNoteAndRmsJs(String noteName, double normalizedRms) {
    final pct = (normalizedRms * 100).clamp(0, 100).toStringAsFixed(0);
    return '''
      (function() {
        var nl=document.getElementById('fk-note-label');
        if(nl) nl.textContent='$noteName';
        var dot=document.getElementById('fk-mic-dot');
        if(!dot)return;
        var n=$pct/100;
        if(n>0.05){
          var sz=10+n*8;
          dot.style.width=sz+'px';dot.style.height=sz+'px';
          dot.style.background='rgb(0,'+Math.round(180+n*75)+',255)';
          dot.style.boxShadow='0 0 '+Math.round(n*25)+'px rgba(0,210,255,'+(n*0.8).toFixed(2)+')';
        } else {
          dot.style.width='10px';dot.style.height='10px';
          dot.style.background='#333';dot.style.boxShadow='none';
        }
      })();
    ''';
  }

  static String celebrationJs(int score) {
    String phrase, emoji;
    if (score >= 90) { phrase = 'SUPERSTAR!'; emoji = '\u{1F31F}'; }
    else if (score >= 75) { phrase = 'Well Done!'; emoji = '\u{1F389}'; }
    else if (score >= 50) { phrase = 'Nice Try!'; emoji = '\u{1F44F}'; }
    else if (score >= 25) { phrase = 'Almost There!'; emoji = '\u{1F4AA}'; }
    else { phrase = 'Keep Practicing!'; emoji = '\u{1F3A4}'; }
    return '''
      (function() {
        var old=document.getElementById('fk-celebration');if(old)old.remove();
        var c=document.createElement('div');c.id='fk-celebration';
        c.style.cssText='position:fixed;inset:0;z-index:999999;'
          +'background:rgba(0,0,0,0.85);display:flex;flex-direction:column;'
          +'align-items:center;justify-content:center;pointer-events:none;'
          +'animation:fkFadeIn 0.5s ease-out;font-family:system-ui,sans-serif;';
        var em=document.createElement('div');
        em.style.cssText='font-size:80px;margin-bottom:16px;animation:fkBounce 0.6s ease-out;';
        em.textContent='$emoji';c.appendChild(em);
        var ph=document.createElement('div');
        ph.style.cssText='font-size:48px;font-weight:800;color:#fff;margin-bottom:8px;'
          +'text-shadow:0 0 30px rgba(255,215,0,0.6);animation:fkSlideUp 0.5s ease-out 0.2s both;';
        ph.textContent='$phrase';c.appendChild(ph);
        var sc=document.createElement('div');
        sc.style.cssText='font-size:96px;font-weight:900;line-height:1;margin:16px 0;'
          +'animation:fkSlideUp 0.5s ease-out 0.4s both;';
        if($score>=75){sc.style.color='#ffd700';sc.style.textShadow='0 0 40px rgba(255,215,0,0.8),0 0 80px rgba(255,215,0,0.4)';}
        else if($score>=50){sc.style.color='#00ff88';sc.style.textShadow='0 0 30px rgba(0,255,136,0.6)';}
        else{sc.style.color='#00d2ff';sc.style.textShadow='0 0 20px rgba(0,210,255,0.5)';}
        sc.textContent='$score';c.appendChild(sc);
        var pt=document.createElement('div');
        pt.style.cssText='font-size:18px;color:rgba(255,255,255,0.5);letter-spacing:6px;'
          +'animation:fkSlideUp 0.5s ease-out 0.5s both;';
        pt.textContent='POINTS';c.appendChild(pt);
        var colors=['#ffd700','#ff6b6b','#00d2ff','#00ff88','#ff9f43','#6c5ce7'];
        for(var i=0;i<30;i++){
          var p=document.createElement('div');
          var sz=3+Math.random()*5,dl=Math.random()*1.5;
          var cl=colors[Math.floor(Math.random()*colors.length)];
          p.style.cssText='position:absolute;left:'+Math.random()*100+'%;top:'+Math.random()*100+'%;'
            +'width:'+sz+'px;height:'+sz+'px;border-radius:50%;background:'+cl+';pointer-events:none;'
            +'animation:fkSparkle 1.5s ease-out '+dl.toFixed(2)+'s both;box-shadow:0 0 '+(sz*3)+'px '+cl+';';
          c.appendChild(p);
        }
        var st=document.createElement('style');
        st.textContent='@keyframes fkFadeIn{from{opacity:0}to{opacity:1}}'
          +'@keyframes fkBounce{0%{transform:scale(0)}50%{transform:scale(1.3)}100%{transform:scale(1)}}'
          +'@keyframes fkSlideUp{from{opacity:0;transform:translateY(30px)}to{opacity:1;transform:translateY(0)}}'
          +'@keyframes fkSparkle{0%{opacity:1;transform:scale(1)}100%{opacity:0;transform:scale(0) translateY(-50px)}}';
        c.appendChild(st);
        document.body.appendChild(c);
        setTimeout(function(){if(c.parentNode)c.style.animation='fkFadeIn 0.5s ease-out reverse';
          setTimeout(function(){if(c.parentNode)c.remove();},500);},6000);
      })();
    ''';
  }

  static String updateSingerJs(String name) => '''
    (function(){var el=document.getElementById('fk-singer');if(el)el.textContent='$name';})();
  ''';

  static const removeOverlayJs = '''
    (function() {
      var el=document.getElementById('fk-overlay');if(el)el.remove();
      delete window._fkTrail;delete window._fkTrailMax;
    })();
  ''';
}
