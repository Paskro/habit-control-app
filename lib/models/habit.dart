class Habit {
  final String name;
  final int points;

  Habit({
    required this.name,
    required this.points,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'points': points,
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      name: json['name'],
      points: json['points'],
    );
  }
}