/// JavaScript to inject a scoring overlay into the YouTube webview.
///
/// Uses DOM createElement (not innerHTML) to comply with YouTube's
/// Trusted Types Content Security Policy.
class WebviewOverlay {
  /// Shared JS helper that creates a hoverable round button.
  /// Buttons are placed on the LEFT side to avoid YouTube's top-right controls.
  /// Click events are stopped from propagating to YouTube elements underneath.
  static const _buttonHelperJs = '''
    if (!window._fkBtn) {
      window._fkBtn = function(id, icon, top, hoverColor, handler) {
        var btn = document.createElement('div');
        btn.id = id;
        btn.textContent = icon;
        btn.style.cssText = 'position:fixed;top:' + top + 'px;left:14px;z-index:100000;'
          + 'width:40px;height:40px;border-radius:50%;'
          + 'background:rgba(0,0,0,0.8);color:rgba(255,255,255,0.6);'
          + 'font-size:22px;display:flex;align-items:center;justify-content:center;'
          + 'cursor:pointer;pointer-events:auto;'
          + 'border:1px solid rgba(255,255,255,0.2);transition:all 0.2s ease;'
          + 'user-select:none;-webkit-user-select:none;';
        btn.addEventListener('mouseenter', function() {
          btn.style.color = hoverColor;
          btn.style.borderColor = hoverColor.replace(')', ',0.5)').replace('rgb', 'rgba');
          btn.style.boxShadow = '0 0 15px ' + hoverColor.replace(')', ',0.3)').replace('rgb', 'rgba');
        });
        btn.addEventListener('mouseleave', function() {
          btn.style.color = 'rgba(255,255,255,0.6)';
          btn.style.borderColor = 'rgba(255,255,255,0.2)';
          btn.style.boxShadow = 'none';
        });
        btn.addEventListener('click', function(e) {
          e.stopPropagation();
          e.preventDefault();
          if (window.webkit && window.webkit.messageHandlers &&
              window.webkit.messageHandlers[handler]) {
            window.webkit.messageHandlers[handler].postMessage('click');
          }
        }, true);
        btn.addEventListener('mousedown', function(e) {
          e.stopPropagation();
        }, true);
        return btn;
      };
    }
  ''';

  /// Settings gear only (for non-video pages like YouTube homepage).
  static const injectSettingsOnlyJs = '''
    (function() {
      if (document.getElementById('fk-settings-btn')) return;
      $_buttonHelperJs
      document.body.appendChild(
        window._fkBtn('fk-settings-btn', '\\u2699', 14, 'rgb(0,210,255)', 'FrankSettings')
      );
    })();
  ''';

  /// Full scoring overlay (for video pages).
  static String injectOverlayJs({required String singerName}) => '''
    (function() {
      var existing = document.getElementById('fk-overlay');
      if (existing) existing.remove();
      var standaloneGear = document.getElementById('fk-settings-btn');
      if (standaloneGear && !standaloneGear.closest('#fk-overlay')) standaloneGear.remove();

      $_buttonHelperJs

      var overlay = document.createElement('div');
      overlay.id = 'fk-overlay';

      // Song title (top center-left, away from YouTube controls)
      var singer = document.createElement('div');
      singer.id = 'fk-singer';
      singer.textContent = '$singerName';
      singer.style.cssText = 'position:fixed;top:14px;left:60px;z-index:99999;'
        + 'background:linear-gradient(135deg,rgba(108,92,231,0.85),rgba(0,0,0,0.7));'
        + 'color:#fff;padding:10px 18px;border-radius:24px;'
        + 'font-family:system-ui,sans-serif;font-size:14px;font-weight:600;'
        + 'pointer-events:none;max-width:40%;'
        + 'overflow:hidden;text-overflow:ellipsis;white-space:nowrap;'
        + 'box-shadow:0 2px 20px rgba(108,92,231,0.4);';
      overlay.appendChild(singer);

      // Current note + mic indicator (top right, but below YouTube bar)
      var noteBox = document.createElement('div');
      noteBox.id = 'fk-note-box';
      noteBox.style.cssText = 'position:fixed;top:56px;right:14px;z-index:99999;'
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

      // Action buttons (left side, below logo area)
      overlay.appendChild(window._fkBtn('fk-settings-btn', '\\u2699', 14, 'rgb(0,210,255)', 'FrankSettings'));
      overlay.appendChild(window._fkBtn('fk-restart-btn', '\\u21BB', 60, 'rgb(255,159,67)', 'FrankRestart'));

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

      // Pitch canvas (bottom left)
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

      document.body.appendChild(overlay);

      window._fkTrail = [];
      window._fkTrailMax = 480;
    })();
  ''';

  static String updateScoreJs(int score) {
    String color, glow, feedback;
    if (score >= 90) {
      color = '#ffd700'; glow = '0 0 30px rgba(255,215,0,0.7)'; feedback = 'AMAZING!';
    } else if (score >= 75) {
      color = '#00ff88'; glow = '0 0 20px rgba(0,255,136,0.5)'; feedback = 'Great singing!';
    } else if (score >= 50) {
      color = '#00d2ff'; glow = '0 0 20px rgba(0,210,255,0.4)'; feedback = 'Keep it up!';
    } else if (score >= 25) {
      color = '#ff9f43'; glow = '0 0 15px rgba(255,159,67,0.4)'; feedback = 'Getting there...';
    } else {
      color = '#ff6b6b'; glow = '0 0 15px rgba(255,107,107,0.3)'; feedback = '';
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

  /// Voice pitch trail with note guide lines. No reference track
  /// (YouTube blocks Web Audio API via CORS on cross-origin video).
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

        // Note grid lines
        var nf=[130.81,261.63,523.25,1046.50], nn=['C3','C4','C5','C6'];
        ctx.font='9px system-ui';
        for(var n=0;n<nf.length;n++){
          var ny=(nf[n]-80)/720; if(ny<0||ny>1)continue;
          var y=h-(ny*(h-2*pad))-pad;
          ctx.strokeStyle='rgba(255,255,255,0.06)'; ctx.lineWidth=1;
          ctx.beginPath();ctx.moveTo(24,y);ctx.lineTo(w,y);ctx.stroke();
          ctx.fillStyle='rgba(255,255,255,0.2)';ctx.fillText(nn[n],2,y+3);
        }

        // Voice trail
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
      var gear=document.getElementById('fk-settings-btn');if(gear)gear.remove();
      delete window._fkTrail;delete window._fkTrailMax;delete window._fkBtn;
    })();
  ''';
}
