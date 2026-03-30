import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'sheet_cache.dart';

class ProjectService {
  static const _prefKey = 'projects_list';

  // In-memory cache: project name -> last used timestamp
  static Map<String, DateTime> _projects = {};
  static bool _loaded = false;

  /// Load projects from local storage.
  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _projects = map.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
    }
    _loaded = true;
  }

  /// Save projects to local storage.
  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _projects.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString(_prefKey, jsonEncode(map));
  }

  /// Get projects sorted by most recently used.
  static Future<List<String>> getProjects() async {
    await _ensureLoaded();
    final sorted = _projects.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  /// Mark a project as just used (moves it to top of list).
  static Future<void> markUsed(String project) async {
    await _ensureLoaded();
    _projects[project] = DateTime.now();
    await _save();
  }

  /// Sync local project list with the SheetCache's Project column.
  /// Hard sync: adds new ones from cache, removes ones no longer in cache,
  /// preserves local usage timestamps for existing ones.
  static Future<void> syncWithCache() async {
    await _ensureLoaded();
    try {
      final sheetProjects = SheetCache.getProjects();
      final sheetSet = sheetProjects.toSet();

      // Remove projects no longer in sheet
      _projects.removeWhere((k, v) => !sheetSet.contains(k));

      // Add new projects from sheet (with old timestamp so they sort below recently used)
      final defaultTime = DateTime(2000);
      for (final p in sheetProjects) {
        _projects.putIfAbsent(p, () => defaultTime);
      }

      await _save();
    } catch (e) {
      print('Project sync error: $e');
      // Silently fail - local list is still usable
    }
  }

  /// Clear local cache (e.g., when switching spreadsheets).
  static Future<void> clear() async {
    _projects.clear();
    _loaded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
