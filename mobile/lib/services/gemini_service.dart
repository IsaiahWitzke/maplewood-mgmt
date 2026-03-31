import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'sheet_cache.dart';

class ReceiptData {
  final String receiptNumber;
  final String vendor;
  final String? date;
  final double? total;
  final double? tax;
  final String? description;

  ReceiptData({
    required this.receiptNumber,
    required this.vendor,
    this.date,
    this.total,
    this.tax,
    this.description,
  });

  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    return ReceiptData(
      receiptNumber: json['receipt_number']?.toString() ?? '',
      vendor: json['vendor']?.toString() ?? '',
      date: json['date']?.toString(),
      total: _toDouble(json['total']),
      tax: _toDouble(json['tax']),
      description: json['description']?.toString(),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

class GeminiService {
  static const _model = 'gemini-2.5-flash';
  static const _apiBase =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static String _buildPrompt() {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Feed known vendors so Gemini can match existing names
    final knownVendors = SheetCache.getVendors();
    final vendorHint = knownVendors.isNotEmpty
        ? '\nKnown vendors (reuse one of these if it matches): ${knownVendors.join(', ')}\n'
        : '';

    return '''Extract the following fields from this receipt image.
Return ONLY valid JSON with these exact keys:
{
  "receipt_number": "receipt or invoice number",
  "vendor": "store name",
  "date": "YYYY-MM-DD",
  "total": 0.00,
  "tax": 0.00,
  "description": "brief category of items"
}

Today's date is $today. Use this to resolve ambiguous dates on the receipt.
For example, "25/03/26" on a receipt near today's date means 2026-03-25, not 2025-03-26.
Receipt dates are almost always within the last few days of today.
$vendorHint
Rules:
- receipt_number = any unique identifier on the receipt (transaction #, invoice #, receipt #, order #). If none found, use null.
- vendor = store/supplier name, always lowercase (e.g. "costco wholesale" not "COSTCO WHOLESALE"). If it matches a known vendor above, use that exact spelling.
- total = final amount paid
- tax = HST / tax amount (this is Ontario, Canada - HST is 13%)
- description = a very brief summary of what was purchased (1-3 words). Examples: "lumber", "plumbing, electrical", "paint supplies", "fasteners". If unclear, use null.
- If a field is not visible or unclear, use null
- Amounts must be numbers, not strings
- Date must be YYYY-MM-DD or null
''';
  }

  /// Extract receipt data from image bytes using Gemini via REST + OAuth.
  static Future<ReceiptData> extractReceipt(Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);
    final url = Uri.parse('$_apiBase/$_model:generateContent');
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': _buildPrompt()},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 10000,
        'responseMimeType': 'application/json',
      }
    });

    var headers = await AuthService.getAuthHeaders();
    var response = await http.post(
      url,
      headers: {...headers, 'Content-Type': 'application/json'},
      body: body,
    );

    // Retry once with a fresh token on 401
    if (response.statusCode == 401) {
      AuthService.invalidateToken();
      headers = await AuthService.getAuthHeaders();
      response = await http.post(
        url,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: body,
      );
    }

    if (response.statusCode != 200) {
      throw Exception('Gemini API error ${response.statusCode}: ${response.body}');
    }

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = responseJson['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('No response from Gemini');
    }

    final parts = candidates[0]['content']['parts'] as List;
    final rawText = parts[0]['text'] as String;
    print('Gemini raw response: $rawText');

    // Strip markdown fences if present
    var cleaned = rawText.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(cleaned.indexOf('\n') + 1);
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trim();
      }
    }

    // Parse JSON with truncation repair
    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      return ReceiptData.fromJson(parsed);
    } catch (_) {
      if (!cleaned.endsWith('}')) cleaned += '}';
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      return ReceiptData.fromJson(parsed);
    }
  }
}
