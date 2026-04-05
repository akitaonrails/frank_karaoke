/// Selectable scoring strategies.
///
/// Each mode uses a different algorithm to evaluate how well the singer
/// matches the music. All modes use pitch stability and dynamics as
/// secondary factors — the primary difference is in how they compare
/// the singer's pitch against the reference.
enum ScoringMode {
  pitchClass(
    label: 'Pitch Match',
    description: 'Match the song\'s notes (octave-agnostic, like SingStar)',
    icon: '🎯',
  ),
  contour(
    label: 'Contour',
    description: 'Follow the melody\'s shape (up/down movement)',
    icon: '〰️',
  ),
  interval(
    label: 'Intervals',
    description: 'Match the jumps between notes (key-agnostic)',
    icon: '📐',
  ),
  streak(
    label: 'Streak',
    description: 'Combo multiplier — consecutive hits build your score',
    icon: '🔥',
  );

  const ScoringMode({
    required this.label,
    required this.description,
    required this.icon,
  });

  final String label;
  final String description;
  final String icon;
}
