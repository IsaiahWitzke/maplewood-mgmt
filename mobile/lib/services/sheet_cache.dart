import '../config.dart';
import 'auth_service.dart';
import 'sheets_service.dart';

/// Known column names. The user can rename/reorder columns in the sheet —
/// the app matches by header text in row 1.
class Col {
  static const receiptNumber = 'Receipt #';
  static const project = 'Project';
  static const vendor = 'Vendor';
  static const totalCost = 'Total Cost';
  static const tax = 'Tax';
  static const receiptDate = 'Receipt Date';
  static const inputDate = 'Input Date';
  static const image = 'Image';
  static const description = 'Description';

  /// Default header order when creating a new spreadsheet.
  static const defaultHeaders = [
    receiptNumber, project, vendor, totalCost, tax, receiptDate, inputDate, image, description,
  ];
}

/// In-memory cache of the active spreadsheet's data.
/// All reads (duplicates, projects) come from here — no extra API calls.
class SheetCache {
  // Header name -> column index (0-based)
  static Map<String, int> _columns = {};
  static List<String> _headers = [];
  // All data rows (excluding header), each keyed by header name
  static List<Map<String, String>> _rows = [];

  static List<String> get headers => List.unmodifiable(_headers);
  static List<Map<String, String>> get rows => List.unmodifiable(_rows);
  static bool get isEmpty => _headers.isEmpty;

  // --- Refresh / Sync ---

  /// Full refresh — reads the entire sheet into memory.
  static Future<void> refresh() async {
    final spreadsheetId = await SheetsService.getSpreadsheetId();
    if (spreadsheetId == null || spreadsheetId.isEmpty) return;

    try {
      final api = await AuthService.getSheetsApi();
      final response = await api.spreadsheets.values.get(
        spreadsheetId,
        AppConfig.sheetName,
      );

      final rawRows = response.values;
      if (rawRows == null || rawRows.isEmpty) return;

      _setHeaders(rawRows.first.map((e) => e?.toString() ?? '').toList());
      _rows = [];
      for (final raw in rawRows.skip(1)) {
        _rows.add(_parseRawRow(raw));
      }
    } catch (e) {
      print('SheetCache refresh error: $e');
      if (_headers.isEmpty) _setHeaders(Col.defaultHeaders);
    }
  }

  /// Incremental sync — checks if the sheet has more rows than we expect.
  /// If so, does a full refresh. Call this after OCR / before showing review.
  static Future<void> sync() async {
    final spreadsheetId = await SheetsService.getSpreadsheetId();
    if (spreadsheetId == null || spreadsheetId.isEmpty) return;

    try {
      final api = await AuthService.getSheetsApi();
      // Read just column A to get the row count (lightweight)
      final response = await api.spreadsheets.values.get(
        spreadsheetId,
        '${AppConfig.sheetName}!A:A',
      );

      final sheetRowCount = (response.values?.length ?? 1) - 1; // minus header
      if (sheetRowCount != _rows.length) {
        // Row count mismatch — someone added/deleted rows externally
        await refresh();
      }
    } catch (e) {
      print('SheetCache sync error: $e');
      // On error, try a full refresh as fallback
      await refresh();
    }
  }

  /// Clear everything (call when switching spreadsheets).
  static void clear() {
    _columns.clear();
    _headers.clear();
    _rows.clear();
  }

  // --- Local cache updates ---

  /// Add a row to the local cache after a successful sheet append.
  static void addRow(Map<String, String> row) {
    _rows.add(row);
  }

  // --- Query helpers (all from cache, no API calls) ---

  /// Find rows matching the given date and total.
  static List<Map<String, String>> findDuplicates({
    required String date,
    required double? total,
  }) {
    if (date.isEmpty && total == null) return [];

    return _rows.where((row) {
      final rowDate = row[Col.receiptDate] ?? '';
      final rowTotal = double.tryParse(row[Col.totalCost] ?? '');

      final dateMatch = date.isNotEmpty && rowDate == date;
      final totalMatch = total != null && rowTotal != null &&
          (total - rowTotal).abs() < 0.01;

      return dateMatch && totalMatch;
    }).toList();
  }

  /// Get unique project names from cached data.
  static List<String> getProjects() {
    final projects = <String>{};
    for (final row in _rows) {
      final p = row[Col.project] ?? '';
      if (p.isNotEmpty) projects.add(p);
    }
    return projects.toList();
  }

  /// Get unique vendor names from cached data.
  static List<String> getVendors() {
    final vendors = <String>{};
    for (final row in _rows) {
      final v = row[Col.vendor] ?? '';
      if (v.isNotEmpty) vendors.add(v);
    }
    return vendors.toList();
  }

  // --- Row building ---

  /// Build a row List (for Sheets API append) from a map of column name -> value.
  static List<dynamic> buildRow(Map<String, dynamic> data) {
    final h = _headers.isNotEmpty ? _headers : Col.defaultHeaders;
    final row = List<dynamic>.filled(h.length, '');
    for (final entry in data.entries) {
      final idx = _headers.isNotEmpty
          ? _columns[entry.key]
          : Col.defaultHeaders.indexOf(entry.key);
      if (idx != null && idx >= 0) row[idx] = entry.value ?? '';
    }
    return row;
  }

  /// Build a Map<String, String> from the same data (for local cache addRow).
  static Map<String, String> buildRowMap(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  // --- Internal ---

  static void _setHeaders(List<String> headers) {
    _headers = headers;
    _columns = {};
    for (var i = 0; i < headers.length; i++) {
      _columns[headers[i]] = i;
    }
  }

  static Map<String, String> _parseRawRow(List<dynamic> raw) {
    final map = <String, String>{};
    for (var i = 0; i < _headers.length && i < raw.length; i++) {
      map[_headers[i]] = raw[i]?.toString() ?? '';
    }
    return map;
  }
}
