import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'services/storage_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: EntryPoint(),
    );
  }
}

class EntryPoint extends StatefulWidget {
  const EntryPoint({super.key});

  @override
  State<EntryPoint> createState() => _EntryPointState();
}

class _EntryPointState extends State<EntryPoint> {
  bool isLoading = true;
  bool hasActiveSession = false;

  @override
  void initState() {
    super.initState();
    checkState();
  }

  Future<void> checkState() async {
    final prefs = await SharedPreferences.getInstance();
    final habits = prefs.getStringList('habits') ?? [];

    setState(() {
      hasActiveSession = habits.isNotEmpty;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (hasActiveSession) {
      return const HomeScreen();
    }

    return WelcomeScreen();
  }
}

class Habit {
  final String name;
  final int points;

  Habit({required this.name, required this.points});

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

enum SessionMode {
  manualLimit,
  stats3,
  stats7,
}

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
          .map((e) => DayRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum Phase {
  statistics,
  control,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final StorageService storage = StorageService();
  int todayPoints = 0;
  List<DayRecord> history = [];
  Phase phase = Phase.statistics;
  SessionMode? sessionMode;
  int statsTargetDays = 7;
  int controlDaysCounter = 0;
  List<Session> sessions = [];
  int currentSessionId = 1;
  bool autoEndDay = true;
  Map<String, int> todayHabits = {};
  int statisticsDaysTarget = 7;
  int currentDayIndex = 0;
  int avgPoints = 0;
  double reductionPercent = 0.1;
  int dailyLimit = 10;
  bool yesterdayExceeded = false;
  List<Habit> habits = [];

  List<DayRecord> get currentSessionHistory {
    return history
        .where((e) => e.sessionId == currentSessionId)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadData().then((_) async {
      if (autoEndDay) {
        await checkMissedDays();
      }
      if (habits.isEmpty) {
        openHabitSetup();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshData();

      Future.delayed(const Duration(milliseconds: 300), () async {
        await checkMissedDays();

        // 🔥 МИНИ-ФИКС: фиксируем день при возврате в приложение
        if (todayPoints > 0 || todayHabits.isNotEmpty) {
          await endDay();
        }
      });
    }
  }

  Future<int?> askManualLimit() async {
    final controller = TextEditingController();

    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Дневной лимит"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Введите лимит (баллы)",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              Navigator.pop(context, value);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshData() async {
    await loadData();
    if (autoEndDay) {
      await checkMissedDays();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> checkMissedDays() async {
    final data = currentSessionHistory;
    if (data.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final lastRecord = data.reduce((a, b) {
      return DateTime.parse(a.date).isAfter(DateTime.parse(b.date)) ? a : b;
    });

    final lastDateParts = lastRecord.date.split("-");
    final lastDate = DateTime(
      int.parse(lastDateParts[0]),
      int.parse(lastDateParts[1]),
      int.parse(lastDateParts[2]),
    );

    int diff = today.difference(lastDate).inDays;
    if (diff <= 0) return;

    final firstMissedDate = lastDate.add(const Duration(days: 1));
    final firstDateStr =
        "${firstMissedDate.year}-${firstMissedDate.month.toString().padLeft(2, '0')}-${firstMissedDate.day.toString().padLeft(2, '0')}";

    final firstRecord = DayRecord(
      date: firstDateStr,
      points: todayPoints,
      exceeded: phase == Phase.control && todayPoints > dailyLimit,
      habits: Map.from(todayHabits),
      sessionId: currentSessionId,
    );

    setState(() {
      history.add(firstRecord);
      yesterdayExceeded = firstRecord.exceeded;
      todayPoints = 0;
      todayHabits.clear();
      if (phase == Phase.statistics) {
        currentDayIndex++;
      }
    });

    for (int i = 2; i <= diff; i++) {
      final missedDate = lastDate.add(Duration(days: i));
      final dateStr =
          "${missedDate.year}-${missedDate.month.toString().padLeft(2, '0')}-${missedDate.day.toString().padLeft(2, '0')}";

      final missedRecord = DayRecord(
        date: dateStr,
        points: 0,
        exceeded: false,
        habits: {},
        sessionId: currentSessionId,
      );

      setState(() {
        history.add(missedRecord);
        yesterdayExceeded = false;
        if (phase == Phase.statistics) {
          currentDayIndex++;
        }
      });
    }

    if (phase == Phase.statistics &&
        currentDayIndex >= statisticsDaysTarget) {
      avgPoints = calculateAverage();
      dailyLimit = calculateLimit(avgPoints);
      phase = Phase.control;
    }

    await saveData();
  }

Future<void> openHabitSetup() async {
  final names = await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => HabitNameScreen()),
  );

  if (names == null || names.isEmpty) return;

  final habitsResult = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => HabitPointsScreen(names: names),
    ),
  );

  if (habitsResult == null) return;

  final modeResult = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const SessionModeScreen(),
    ),
  );

  if (modeResult == null) return;

  final mode = modeResult["mode"] as SessionMode;
  final days = modeResult["days"] as int;

  int? limit;

  if (mode == SessionMode.manualLimit) {
    limit = await askManualLimit();

    if (limit == null || limit <= 0) return;
  }

  setState(() {
    habits = habitsResult;
    sessionMode = mode;

    if (mode == SessionMode.manualLimit) {
      statsTargetDays = 0;
      phase = Phase.control;
      avgPoints = 0;
      dailyLimit = limit!;
    } else {
      statsTargetDays = days;
      statisticsDaysTarget = days;
      phase = Phase.statistics;
      currentDayIndex = 0;
    }
  });

  await saveData();
}

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final historyJson = prefs.getStringList('history') ?? [];
    final sessionsJson = prefs.getStringList('sessions') ?? [];
    currentSessionId = prefs.getInt('currentSessionId') ?? 1;



    final habitsMapString = prefs.getString('todayHabits');

    if (habitsMapString != null) {
      todayHabits = Map<String, int>.from(jsonDecode(habitsMapString));
    }

    final raw = await storage.loadStringList('habits');
    habits = raw.map((e) => Habit.fromJson(jsonDecode(e))).toList();

    setState(() {
      todayPoints = prefs.getInt('todayPoints') ?? 0;
      yesterdayExceeded = prefs.getBool('yesterdayExceeded') ?? false;
      phase = Phase.values[prefs.getInt('phase') ?? 0];
      currentDayIndex = prefs.getInt('currentDayIndex') ?? 0;
      avgPoints = prefs.getInt('avgPoints') ?? 0;
      dailyLimit = prefs.getInt('dailyLimit') ?? 10;
      reductionPercent = prefs.getDouble('reductionPercent') ?? 0.1;

      history = historyJson
          .map((e) => DayRecord.fromJson(jsonDecode(e)))
          .toList();

      sessions = sessionsJson
          .map((e) => Session.fromJson(jsonDecode(e)))
          .toList();
    });
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('todayPoints', todayPoints);
    await prefs.setBool('yesterdayExceeded', yesterdayExceeded);
    await prefs.setInt('phase', phase.index);
    await prefs.setInt('currentDayIndex', currentDayIndex);
    await prefs.setInt('avgPoints', avgPoints);
    await prefs.setInt('dailyLimit', dailyLimit);
    await prefs.setDouble('reductionPercent', reductionPercent);
    await prefs.setString('todayHabits', jsonEncode(todayHabits));

    final historyJson = history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('history', historyJson);

    final sessionsJson = sessions.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('sessions', sessionsJson);
    await prefs.setInt('currentSessionId', currentSessionId);

    final raw = habits.map((e) => jsonEncode(e.toJson())).toList();
    await storage.saveStringList('habits', raw);
  }

  void addHabit(Habit habit) {
    setState(() {
      todayPoints += habit.points;
      todayHabits[habit.name] =
          (todayHabits[habit.name] ?? 0) + 1;
    });
    saveData();
  }

  int calculateAverage() {
    final data = currentSessionHistory;
    if (data.isEmpty) return 0;

    int count = statisticsDaysTarget;
    if (data.length < count) {
      count = data.length;
    }

    final lastDays = data.sublist(data.length - count);
    int sum = lastDays.fold(0, (prev, e) => prev + e.points);

    return (sum / lastDays.length).round();
  }

  int calculateLimit(int avg) {
    if (avg <= 0) return 0;

    int reduced = (avg * (1 - reductionPercent)).floor();
    if (reduced >= avg) {
      return avg - 1;
    }
    return reduced;
  }

  Future<void> askReductionPercent() async {
    final controller = TextEditingController(
      text: (reductionPercent * 100).toInt().toString(),
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Снижение привычек"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: "Процент (%)"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );

    final value = double.tryParse(controller.text) ?? 10.0;
    setState(() {
      reductionPercent = (value / 100).clamp(0.01, 0.99);
    });
  }

  Future<void> endDay() async {
    final now = DateTime.now();
    final today =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final data = currentSessionHistory;
    if (data.isNotEmpty) {
      final last = data.last;
      if (last.date == today && last.sessionId == currentSessionId) {
        return;
      }
    }

    final record = DayRecord(
      date: today,
      points: todayPoints,
      exceeded: phase == Phase.control &&
          todayPoints > dailyLimit,
      habits: Map.from(todayHabits),
      sessionId: currentSessionId,
    );

    bool shouldUpdatePhase = false;

    if (phase == Phase.statistics) {
      final newIndex = currentDayIndex + 1;
      if (sessionMode != SessionMode.manualLimit &&
          newIndex >= statsTargetDays) {
        avgPoints = calculateAverage();
        await askReductionPercent();
        dailyLimit = calculateLimit(avgPoints);
        shouldUpdatePhase = true;
      }
    }

    setState(() {
      history.add(record);
      yesterdayExceeded = record.exceeded;
      todayPoints = 0;
      todayHabits.clear();
      if (phase == Phase.statistics) {
        currentDayIndex++;
        if (currentDayIndex >= statisticsDaysTarget &&
            shouldUpdatePhase) {
          phase = Phase.control;
        }
      }
    });

    saveData();
  }

  void resetSession() {
    if (currentSessionHistory.isNotEmpty) {
      final data = currentSessionHistory;
      final session = Session(
        id: sessions.length + 1,
        days: List.from(currentSessionHistory),
        avg: avgPoints,
        totalPoints: currentSessionHistory.fold(
            0, (sum, e) => sum + e.points),
        controlDays:
            (data.length - statisticsDaysTarget).clamp(0, 999),
      );
      sessions.add(session);
      currentSessionId++;
    }

    saveData().then((_) {
      setState(() {
        habits.clear();
        phase = Phase.statistics;
        currentDayIndex = 0;
        avgPoints = 0;
        dailyLimit = 10;
        todayPoints = 0;
        yesterdayExceeded = false;
        todayHabits.clear();
      });
      saveData().then((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const SessionCompleteScreen(),
          ),
        );
      });
    });
  }

  int getRemaining() {
    if (phase == Phase.statistics) {
      return todayPoints;
    }
    return dailyLimit - todayPoints;
  }

  Future<void> showControlAdjustmentDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Контрольный пересмотр"),
        content: const Text(
          "Хотите изменить настройки контроля?",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              askReductionPercent();
            },
            child: const Text("Изменить %"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              increaseHabitValues();
            },
            child: const Text("Изменить привычки"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Позже"),
          ),
        ],
      ),
    );
  }

  void increaseHabitValues() {
    setState(() {
      habits = habits.map((h) {
        return Habit(
          name: h.name,
          points: (h.points + 1).clamp(1, 5),
        );
      }).toList();
    });
    saveData();
  }

  Color getColor() {
    if (phase == Phase.statistics) return Colors.blue;
    final remaining = getRemaining();
    if (remaining > dailyLimit * 0.3) return Colors.green;
    if (remaining > 0) return Colors.orange;
    return Colors.red;
  }

  String getMorningMessage() {
    return yesterdayExceeded
        ? "Вчера ты вышел за предел, сегодня будет лучше!"
        : "Вчера ты был в пределах лимита, так держать!";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Контроль привычек")),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Text(
              phase == Phase.statistics
                  ? "Этап: Сбор статистики (${(currentDayIndex + 1).clamp(1, statisticsDaysTarget)}/$statisticsDaysTarget)"
                  : "Этап: Контроль (лимит: $dailyLimit)",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            if (phase == Phase.control)
              Text(
                getMorningMessage(),
                style: const TextStyle(fontSize: 16),
              ),
            const SizedBox(height: 20),
            Text(
              phase == Phase.statistics
                  ? "Сегодня: ${getRemaining()} баллов"
                  : "Осталось: ${getRemaining()} баллов",
              style: TextStyle(
                fontSize: 24,
                color: getColor(),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.8,
                ),
                itemCount: habits.length,
                itemBuilder: (context, index) {
                  final habit = habits[index];
                  return ElevatedButton(
                    onPressed: () => addHabit(habit),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(10),
                    ),
                    child: Text(
                      "${habit.name} (+${habit.points})",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (todayHabits.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Сегодня по привычкам:",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...todayHabits.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key,
                              style:
                                  const TextStyle(fontSize: 16)),
                          Text(
                            "${e.value}",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: resetSession,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red),
                          child:
                              const Text("Начать заново"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HistoryScreen(
                                    sessions: sessions),
                              ),
                            );
                          },
                          child: const Text("История"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  final List<Session> sessions;

  const HistoryScreen({super.key, required this.sessions});

  Map<String, int> calculateHabitStats(Session session) {
    final stats = <String, int>{};
    for (final day in session.days) {
      for (final entry in day.habits.entries) {
        stats[entry.key] = (stats[entry.key] ?? 0) + entry.value;
      }
    }
    return stats;
  }

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("История сессий")),
        body: const Center(
          child: Text("Еще не закончили ни одной сессии"),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("История сессий")),
      body: ListView.builder(
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final s = sessions[index];
          final stats = calculateHabitStats(s);

          return Card(
            child: ListTile(
              title: Text("Сессия #${s.id}"),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      "Всего: ${s.totalPoints}, Среднее: ${s.avg}, Контроль: ${s.controlDays}"),
                  ...stats.entries
                      .map((e) => Text("${e.key}: ${e.value}")),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class HabitNameScreen extends StatefulWidget {
  const HabitNameScreen({super.key});

  @override
  State<HabitNameScreen> createState() => _HabitNameScreenState();
}

class _HabitNameScreenState extends State<HabitNameScreen> {
  final controllers = List.generate(8, (_) => TextEditingController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Привычки")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: 8,
              itemBuilder: (_, i) {
                return TextField(
                  controller: controllers[i],
                  decoration:
                      InputDecoration(labelText: "Привычка ${i + 1}"),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final names = controllers
                  .map((e) => e.text.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              Navigator.pop(context, names);
            },
            child: const Text("Далее"),
          ),
        ],
      ),
    );
  }
}

class HabitPointsScreen extends StatefulWidget {
  final List<String> names;

  const HabitPointsScreen({super.key, required this.names});

  @override
  State<HabitPointsScreen> createState() => _HabitPointsScreenState();
}

class _HabitPointsScreenState extends State<HabitPointsScreen> {
  late List<int> points;

  @override
  void initState() {
    super.initState();
    points = List.filled(widget.names.length, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Баллы")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.names.length,
              itemBuilder: (_, i) {
                return ListTile(
                  title: Text(widget.names[i]),
                  trailing: DropdownButton<int>(
                    value: points[i],
                    items: List.generate(5, (i) => i + 1)
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text("$e"),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => points[i] = v!);
                    },
                  ),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final habits = List.generate(
                widget.names.length,
                (i) => Habit(name: widget.names[i], points: points[i]),
              );
              Navigator.pop(context, habits);
            },
            child: const Text("Готово"),
          ),
        ],
      ),
    );
  }
}

class SessionModeScreen extends StatelessWidget {
  const SessionModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Режим")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Как будем контролировать привычки?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, {
                    "mode": SessionMode.manualLimit,
                    "days": 0,
                  });
                },
                child: const Text("Сам задам дневной лимит"),
              ),

              const SizedBox(height: 12),

              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, {
                    "mode": SessionMode.stats3,
                    "days": 3,
                  });
                },
                child: const Text("3 дня статистики"),
              ),

              const SizedBox(height: 12),

              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, {
                    "mode": SessionMode.stats7,
                    "days": 7,
                  });
                },
                child: const Text("7 дней статистики"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionCompleteScreen extends StatelessWidget {
  const SessionCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Готово")),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const EntryPoint()),
              (route) => false,
            );
          },
          child: const Text("На главный"),
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Добро пожаловать")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Добро пожаловать!",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HomeScreen(),
                    ),
                  );
                },
                child: const Text("Начать новое приключение"),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final sessionsJson =
                      prefs.getStringList('sessions') ?? [];

                  if (sessionsJson.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Нет завершенных сессий"),
                      ),
                    );
                    return;
                  }

                  final sessions = sessionsJson
                      .map((e) => Session.fromJson(jsonDecode(e)))
                      .toList();

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          HistoryScreen(sessions: sessions),
                    ),
                  );
                },
                child: const Text("Посмотреть историю"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}