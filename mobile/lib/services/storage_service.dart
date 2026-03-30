import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'auth_service.dart';

class StorageService {
  static const _uuid = Uuid();
  static const _folderIdKey = 'receipt_folder_id';
  static const _folderNameKey = 'receipt_folder_name';

  /// Get the saved receipt folder ID (null = Drive root).
  static Future<String?> getReceiptFolderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_folderIdKey);
  }

  /// Get the saved receipt folder name for display.
  static Future<String> getReceiptFolderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_folderNameKey) ?? 'My Drive';
  }

  /// Save the receipt folder selection.
  static Future<void> setReceiptFolder({String? id, required String name}) async {
    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      await prefs.setString(_folderIdKey, id);
    } else {
      await prefs.remove(_folderIdKey);
    }
    await prefs.setString(_folderNameKey, name);
  }

  /// Compress image to ~200KB JPEG and upload to Google Drive.
  /// Returns a shareable Drive link.
  static Future<String> uploadReceiptImage(Uint8List imageBytes) async {
    // Decode and compress
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Failed to decode image');

    // Resize if very large (keep aspect ratio, max 1200px wide)
    final resized =
        decoded.width > 1200 ? img.copyResize(decoded, width: 1200) : decoded;

    // Encode as JPEG with quality 70 (~200KB for a receipt)
    final compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 70));

    // Upload to Drive
    final driveApi = await AuthService.getDriveApi();
    final folderId = await getReceiptFolderId();

    final driveFile = drive.File(
      name: 'receipt_${_uuid.v4()}.jpg',
      parents: [folderId ?? 'root'],
      mimeType: 'image/jpeg',
    );

    final media = drive.Media(
      Stream.value(compressed),
      compressed.length,
      contentType: 'image/jpeg',
    );

    final created = await driveApi.files.create(
      driveFile,
      uploadMedia: media,
      $fields: 'id',
    );

    return 'https://drive.google.com/file/d/${created.id}/view';
  }
}
