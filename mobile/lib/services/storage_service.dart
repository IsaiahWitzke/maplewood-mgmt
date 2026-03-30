import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

class StorageService {
  static final _storage = FirebaseStorage.instance;
  static const _uuid = Uuid();

  /// Compress image to ~200KB JPEG and upload to Firebase Storage.
  /// Returns the public download URL.
  static Future<String> uploadReceiptImage(Uint8List imageBytes) async {
    // Decode and compress
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Failed to decode image');

    // Resize if very large (keep aspect ratio, max 1200px wide)
    final resized =
        decoded.width > 1200 ? img.copyResize(decoded, width: 1200) : decoded;

    // Encode as JPEG with quality 70 (~200KB for a receipt)
    final compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 70));

    // Upload
    final path = 'receipts/${_uuid.v4()}.jpg';
    final ref = _storage.ref().child(path);
    await ref.putData(compressed, SettableMetadata(contentType: 'image/jpeg'));

    // Get download URL (permanent, includes access token)
    return await ref.getDownloadURL();
  }
}
