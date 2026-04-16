class DayRecord {
  final String date;
  final int points;
  final bool exceeded;
  final Map<String, int> habits;
  final int sessionId;

  DayRecord({
    required this.date,
    required this.points,
    required this.exceeded,
    required this.habits,
    required this.sessionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'points': points,
      'exceeded': exceeded,
      'habits': habits,
      'sessionId': sessionId,
    };
  }

  factory DayRecord.fromJson(Map<String, dynamic> json) {
    return DayRecord(
      date: json['date'],
      points: json['points'],
      exceeded: json['exceeded'],
      habits: Map<String, int>.from(json['habits'] ?? {}),
      sessionId: json['sessionId'] ?? 0,
    );
  }
}