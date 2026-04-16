import 'day_record.dart';

class Session {
  final int id;
  final List<DayRecord> days;
  final int avg;
  final int totalPoints;
  final int controlDays;

  Session({
    required this.id,
    required this.days,
    required this.avg,
    required this.totalPoints,
    required this.controlDays,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'avg': avg,
      'totalPoints': totalPoints,
      'controlDays': controlDays,
      'days': days.map((e) => e.toJson()).toList(),
    };
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'],
      avg: json['avg'],
      totalPoints: json['totalPoints'],
      controlDays: json['controlDays'],
      days: (json['days'] as List)
          .map((e) => DayRecord.fromJson(e))
          .toList(),
    );
  }
}