import 'dart:ui' as ui;

/// Simple localization for the app.
/// Detects the device locale and returns translated strings.
/// Supports: English (default), Portuguese (Brazil).
class S {
  static String _lang = 'en';

  /// Initialize from the device's locale. Call once at app startup.
  static void init() {
    final locale = ui.PlatformDispatcher.instance.locale;
    _lang = locale.languageCode == 'pt' ? 'pt' : 'en';
  }

  /// Force a specific language (for testing).
  static void setLanguage(String lang) => _lang = lang;

  static String get lang => _lang;

  // --- App ---
  static String get appName => 'Frank Karaoke';

  // --- Welcome Screen ---
  static String get welcomeSubtitle => _t(
    'Sing along with any YouTube karaoke video',
    'Cante junto com qualquer vídeo de karaokê do YouTube',
  );
  static String get welcomeHowTitle => _t('How it works', 'Como funciona');
  static String get welcomeHowBody => _t(
    'Play any YouTube karaoke video and sing along. The app listens to the music and your voice separately, then scores how well they match in real-time.',
    'Toque qualquer vídeo de karaokê do YouTube e cante junto. O app ouve a música e sua voz separadamente e pontua em tempo real.',
  );
  static String get welcomeScoringTitle => _t('Pick your scoring style', 'Escolha seu estilo de pontuação');
  static String get welcomeScoringBody => _t(
    'Pitch \u2014 are you hitting the right notes? Contour \u2014 are you following the melody shape? Interval \u2014 are your note jumps right? Streak \u2014 party mode with combo multipliers!',
    'Pitch \u2014 você está acertando as notas? Contour \u2014 está seguindo a melodia? Interval \u2014 os saltos entre notas são musicais? Streak \u2014 modo festa com multiplicador combo!',
  );
  static String get welcomeSettingsTitle => _t('Settings (gear icon, top-left)', 'Configurações (ícone de engrenagem)');
  static String get welcomeSettingsBody => _t(
    'Mic preset, scoring mode, pitch shift, and mic calibration. Calibrate first! It listens to your room for 3 seconds to set the right noise level.',
    'Preset de microfone, modo de pontuação, ajuste de tom e calibração. Calibre primeiro! Ele ouve o ambiente por 3 segundos para ajustar o nível de ruído.',
  );
  static String get welcomeCalibrationTip => _t(
    '\u{1F4A1} Tip: Open settings and calibrate your mic before singing. It takes 3 seconds and makes scoring work in any room.',
    '\u{1F4A1} Dica: Abra as configurações e calibre o microfone antes de cantar. Leva 3 segundos e faz a pontuação funcionar em qualquer ambiente.',
  );
  static String get welcomeDontShowAgain => _t("Don't show again", 'Não mostrar novamente');
  static String get welcomeGotIt => _t('Got it!', 'Entendi!');

  // --- Score Display ---
  static String get scoreLabel => 'SCORE';
  static String get overallLabel => 'OVERALL';
  static String get tapToChangeMode => _t('Tap to change mode', 'Toque para mudar o modo');

  // --- Score Feedback ---
  static String get feedbackPerfect => _t('PERFECT!', 'PERFEITO!');
  static String get feedbackIncredible => _t('Incredible!', 'Incrível!');
  static String get feedbackNailingIt => _t('Nailing it!', 'Mandando bem!');
  static String get feedbackSoundingGood => _t('Sounding good!', 'Soando bem!');
  static String get feedbackKeepGoing => _t('Keep going!', 'Continue assim!');
  static String get feedbackWarmingUp => _t('Warming up...', 'Aquecendo...');
  static String get feedbackSingLouder => _t('Sing louder!', 'Cante mais alto!');
  static String get feedbackFindMelody => _t('Find the melody!', 'Encontre a melodia!');
  static String get feedbackStreakBroken => _t('Streak broken!', 'Combo perdido!');
  static String streakCombo(int n) => '\u{1F525} ${n}x COMBO!';
  static String streakOnFire(int n) => '\u{1F525} ${n}x ON FIRE!';
  static String streakCount(int n) => '\u{1F525} ${n}x streak';

  // --- Celebration ---
  static String get celebSuperstar => 'SUPERSTAR!';
  static String get celebWellDone => _t('Well Done!', 'Muito Bem!');
  static String get celebNiceTry => _t('Nice Try!', 'Boa Tentativa!');
  static String get celebAlmostThere => _t('Almost There!', 'Quase Lá!');
  static String get celebKeepPracticing => _t('Keep Practicing!', 'Continue Praticando!');
  static String get celebPoints => _t('POINTS', 'PONTOS');
  static String get celebTapToContinue => _t('Tap anywhere to continue', 'Toque para continuar');

  // --- Settings Panel ---
  static String get micPresetLabel => _t('MIC PRESET', 'PRESET DO MIC');
  static String get pitchShiftLabel => _t('PITCH SHIFT', 'AJUSTE DE TOM');
  static String get restartSong => _t('\u21BB  Restart Song', '\u21BB  Reiniciar Música');
  static String get calibrateMic => _t('\u{1F399} Calibrate Mic', '\u{1F399} Calibrar Microfone');
  static String get presetClean => _t('\u{1F3A4} Clean', '\u{1F3A4} Limpo');
  static String get presetRoom => _t('\u{1F3E0} Room', '\u{1F3E0} Sala');
  static String get presetParty => _t('\u{1F389} Party', '\u{1F389} Festa');

  // --- Calibration ---
  static String calibCountdown(int s) => _t(
    '\u{1F399} Stay quiet... ${s}s',
    '\u{1F399} Fique em silêncio... ${s}s',
  );
  static String get calibMicUnavailable => _t('\u{274C} Mic unavailable', '\u{274C} Mic indisponível');
  static String get calibNoData => _t('\u{274C} No data', '\u{274C} Sem dados');
  static String get calibDone => _t('\u{2705} Calibrated', '\u{2705} Calibrado');

  // --- Processing Overlay ---
  static String get processingLoading => _t('Loading...', 'Carregando...');
  static String get processingLoadingSong => _t('Loading song data...', 'Carregando dados da música...');
  static String get processingSubtitle => _t('First time takes a moment', 'A primeira vez pode demorar um pouco');

  // --- Score Mode Selector ---
  static String get chooseScoringMode => _t('Choose Scoring Mode', 'Escolha o Modo de Pontuação');
  static String get modeSelectorSubtitle => _t(
    'Tap to switch. Song will restart with new scoring.',
    'Toque para trocar. A música reinicia com a nova pontuação.',
  );
  static String get modeActiveBadge => _t('ACTIVE', 'ATIVO');

  // Mode names
  static String get modePitchName => _t('Pitch Match', 'Afinação');
  static String get modeContourName => _t('Contour', 'Contorno');
  static String get modeIntervalName => _t('Intervals', 'Intervalos');
  static String get modeStreakName => _t('Streak', 'Sequência');

  // Mode "best for" labels
  static String get modePitchWhen => _t('Best for songs you know well', 'Melhor para músicas que você conhece');
  static String get modeContourWhen => _t('Best for learning new songs', 'Melhor para aprender músicas novas');
  static String get modeIntervalWhen => _t('Best when singing in another key', 'Melhor para cantar em outro tom');
  static String get modeStreakWhen => _t('Best for parties and competition', 'Melhor para festas e competição');

  // Mode descriptions
  static String get modePitchDesc => _t(
    'Are you hitting the right notes? Detects your pitch and checks if it lands cleanly on musical notes (C, D, E...). Holding steady notes scores higher than wobbling between them.',
    'Você está acertando as notas? Detecta sua afinação e verifica se ela aterrissa precisamente em notas musicais (Dó, Ré, Mi...). Segurar notas firmes pontua mais do que oscilar.',
  );
  static String get modeContourDesc => _t(
    'Are you following the melody shape? Scores whether your voice goes up and down with the music. Does not care which exact note you sing, only the direction and flow.',
    'Você está seguindo o formato da melodia? Pontua se sua voz sobe e desce com a música. Não importa qual nota exata você canta, apenas a direção e o fluxo.',
  );
  static String get modeIntervalDesc => _t(
    'Are your note jumps musical? Steps and thirds score high. Wild octave jumps score low. Rewards proper phrasing regardless of which key you are singing in.',
    'Seus saltos entre notas são musicais? Passos e terças pontuam alto. Saltos de oitava pontuam baixo. Recompensa fraseado musical independente do tom.',
  );
  static String get modeStreakDesc => _t(
    'Pitch scoring with a combo multiplier! Good notes build your streak (5x, 15x, 30x ON FIRE!). One bad note resets to zero. Pauses freeze the streak safely. Most exciting mode!',
    'Pontuação de afinação com multiplicador combo! Notas boas constroem sua sequência (5x, 15x, 30x ON FIRE!). Uma nota ruim zera. Pausas congelam a sequência. O modo mais emocionante!',
  );

  // --- Helper ---
  static String _t(String en, String pt) => _lang == 'pt' ? pt : en;
}
