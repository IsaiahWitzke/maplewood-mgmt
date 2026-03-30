import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'auth_service.dart';
import 'sheet_cache.dart';

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
    final headers = Col.defaultHeaders;
    final lastCol = String.fromCharCode(64 + headers.length); // A=1
    await api.spreadsheets.values.update(
      sheets.ValueRange(values: [headers]),
      id,
      '${AppConfig.sheetName}!A1:${lastCol}1',
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

  /// Append a receipt row using SheetCache for column mapping.
  static Future<void> appendReceipt(Map<String, dynamic> data) async {
    final api = await AuthService.getSheetsApi();
    final spreadsheetId = await ensureSpreadsheet();

    final row = SheetCache.buildRow(data);
    final colCount = row.length;
    final lastCol = String.fromCharCode(64 + colCount); // A=1

    await api.spreadsheets.values.append(
      sheets.ValueRange(values: [row]),
      spreadsheetId,
      '${AppConfig.sheetName}!A:$lastCol',
      valueInputOption: 'USER_ENTERED',
    );

    // Update local cache
    SheetCache.addRow(SheetCache.buildRowMap(data));
  }
}
