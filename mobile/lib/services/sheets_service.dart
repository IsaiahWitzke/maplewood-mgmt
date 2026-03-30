import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'auth_service.dart';

class SheetsService {
  static const _prefKey = 'spreadsheet_id';

  /// Get saved spreadsheet ID from local storage.
  static Future<String?> getSpreadsheetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  /// Save spreadsheet ID to local storage.
  static Future<void> setSpreadsheetId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, id);
  }

  /// Create a new spreadsheet with headers. Returns the spreadsheet ID.
  static Future<String> createSpreadsheet({String? name, String? folderId}) async {
    final api = await AuthService.getSheetsApi();
    final spreadsheet = sheets.Spreadsheet(
      properties: sheets.SpreadsheetProperties(title: name ?? 'Maplewood Receipts'),
      sheets: [
        sheets.Sheet(
          properties: sheets.SheetProperties(title: AppConfig.sheetName),
        ),
      ],
    );

    final created = await api.spreadsheets.create(spreadsheet);
    final id = created.spreadsheetId!;

    // Add headers
    await api.spreadsheets.values.update(
      sheets.ValueRange(values: [
        ['Receipt #', 'Project', 'Vendor', 'Total Cost', 'Tax', 'Receipt Date', 'Input Date', 'Image']
      ]),
      id,
      '${AppConfig.sheetName}!A1:H1',
      valueInputOption: 'RAW',
    );

    // Move to folder if specified
    if (folderId != null && folderId.isNotEmpty) {
      try {
        final driveApi = await AuthService.getDriveApi();
        await driveApi.files.update(
          drive.File(parents: [folderId]),
          id,
          addParents: folderId,
          removeParents: 'root',
        );
      } catch (e) {
        print('Could not move to folder: $e');
      }
    }

    await setSpreadsheetId(id);
    return id;
  }

  /// Get or create the spreadsheet ID.
  static Future<String> ensureSpreadsheet() async {
    final existing = await getSpreadsheetId();
    if (existing != null && existing.isNotEmpty) return existing;
    return await createSpreadsheet();
  }

  /// Append a receipt row.
  static Future<void> appendReceipt({
    required String receiptNumber,
    required String project,
    required String vendor,
    required double? total,
    required double? tax,
    required String receiptDate,
    required String imageLink,
  }) async {
    final api = await AuthService.getSheetsApi();
    final spreadsheetId = await ensureSpreadsheet();
    final inputDate = DateTime.now().toIso8601String();

    await api.spreadsheets.values.append(
      sheets.ValueRange(values: [
        [receiptNumber, project, vendor, total ?? '', tax ?? '', receiptDate, inputDate, imageLink]
      ]),
      spreadsheetId,
      '${AppConfig.sheetName}!A:H',
      valueInputOption: 'USER_ENTERED',
    );
  }

  /// Get unique project names from the sheet, sorted by most recent first.
  static Future<List<String>> getProjects() async {
    final api = await AuthService.getSheetsApi();
    final spreadsheetId = await getSpreadsheetId();
    if (spreadsheetId == null) return [];

    try {
      final response = await api.spreadsheets.values.get(
        spreadsheetId,
        '${AppConfig.sheetName}!B:B', // Project column only
      );

      final rows = response.values;
      if (rows == null || rows.length < 2) return [];

      final projects = <String>{};
      for (final row in rows.skip(1)) {
        if (row.isEmpty) continue;
        final project = row[0]?.toString() ?? '';
        if (project.isNotEmpty) projects.add(project);
      }
      return projects.toList();
    } catch (e) {
      print('Error fetching projects: $e');
      return [];
    }
  }
}
