import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/habit.dart';
import '../models/day_record.dart';
import '../models/session.dart';

class StorageService {
  Future<void> saveHabits(List<Habit> habits) async {
    final prefs = await SharedPreferences.getInstance();
    final json = habits.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('habits', json);
  }

  Future<List<Habit>> loadHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('habits') ?? [];
    return list.map((e) => Habit.fromJson(jsonDecode(e))).toList();
  }

  Future<void> saveHistory(List<DayRecord> history) async {
    final prefs = await SharedPreferences.getInstance();
    final json = history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('history', json);
  }

  Future<List<DayRecord>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('history') ?? [];
    return list.map((e) => DayRecord.fromJson(jsonDecode(e))).toList();
  }

  Future<void> saveSessions(List<Session> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final json = sessions.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('sessions', json);
  }

  Future<List<Session>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('sessions') ?? [];
    return list.map((e) => Session.fromJson(jsonDecode(e))).toList();
  }
}