import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'folder_picker.dart';
import 'onboarding_screen.dart';
import 'spreadsheet_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _receiptFolderName = 'My Drive';
  String _spreadsheetName = '...';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final folderName = await StorageService.getReceiptFolderName();
    final prefs = await SharedPreferences.getInstance();
    // We don't store the sheet name, so fetch it or show a placeholder
    final sheetId = prefs.getString('spreadsheet_id');
    String sheetName = 'Not set';
    if (sheetId != null) {
      try {
        final driveApi = await AuthService.getDriveApi();
        final file = await driveApi.files.get(sheetId) as dynamic;
        sheetName = file.name ?? 'Untitled';
      } catch (_) {
        sheetName = 'Unknown';
      }
    }
    if (mounted) {
      setState(() {
        _receiptFolderName = folderName;
        _spreadsheetName = sheetName;
      });
    }
  }

  Future<void> _pickReceiptFolder() async {
    final result = await Navigator.of(context).push<FolderSelection>(
      MaterialPageRoute(builder: (_) => const DriveFolderPicker()),
    );
    if (result != null) {
      await StorageService.setReceiptFolder(id: result.id, name: result.name);
      setState(() => _receiptFolderName = result.name);
    }
  }

  Future<void> _pickSpreadsheet() async {
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SpreadsheetPickerScreen()),
    );
    if (name != null && mounted) {
      setState(() => _spreadsheetName = name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.grey[50],
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Receipt Spreadsheet
          _buildSettingTile(
            icon: Icons.table_chart,
            iconColor: Colors.green[600]!,
            label: 'Receipt Spreadsheet',
            value: _spreadsheetName,
            onTap: _pickSpreadsheet,
          ),
          const SizedBox(height: 8),

          // Photos Folder
          _buildSettingTile(
            icon: Icons.folder,
            iconColor: Colors.amber[700]!,
            label: 'Photos Folder',
            value: _receiptFolderName,
            onTap: _pickReceiptFolder,
          ),

          // Debug: reset onboarding
          if (kDebugMode) ...[
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _resetOnboarding,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset Onboarding (debug)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[400],
                  side: BorderSide(color: Colors.red[300]!),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _resetOnboarding() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Onboarding?'),
        content: const Text(
            'This will sign you out and clear all settings. You will go through the onboarding flow again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Reset', style: TextStyle(color: Colors.red[400]))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_complete');
    await prefs.remove('receipt_folder_id');
    await prefs.remove('receipt_folder_name');
    await prefs.remove('spreadsheet_id');
    await prefs.remove('projects_list');
    await AuthService.signOut();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (_) => false,
      );
    }
  }
}

