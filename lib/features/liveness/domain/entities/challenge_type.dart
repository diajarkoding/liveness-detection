/// ChallengeType representing the active liveness challenges
enum ChallengeType {
  blink,
  turnLeft,
  turnRight,
  smile;

  /// Get challenge from string name
  static ChallengeType? fromString(String name) {
    return switch (name.toUpperCase()) {
      'BLINK' => ChallengeType.blink,
      'TURN_LEFT' => ChallengeType.turnLeft,
      'TURN_RIGHT' => ChallengeType.turnRight,
      'SMILE' => ChallengeType.smile,
      _ => null,
    };
  }

  /// Get display name for UI
  String get displayName => switch (this) {
    ChallengeType.blink => 'Kedipkan Mata',
    ChallengeType.turnLeft => 'Tengok Kiri',
    ChallengeType.turnRight => 'Tengok Kanan',
    ChallengeType.smile => 'Senyum',
  };

  /// Get instruction text
  String get instruction => switch (this) {
    ChallengeType.blink => 'Kedipkan mata Anda 2 kali',
    ChallengeType.turnLeft => 'Hadap lurus, lalu palingkan ke KIRI',
    ChallengeType.turnRight => 'Hadap lurus, lalu palingkan ke KANAN',
    ChallengeType.smile => 'Tersenyum lebar',
  };
}
