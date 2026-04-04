import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/sheet_cache.dart';
import '../services/sheets_service.dart';
import '../services/storage_service.dart';
import '../services/project_service.dart';
import 'folder_picker.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Step 2: Auth
  bool _signingIn = false;
  String? _authError;

  // Step 3: Camera
  bool _cameraDenied = false;
  bool _cameraPermanentlyDenied = false;

  // Step 4: Combined Drive setup
  bool _createNewFolder = true;
  String? _selectedFolderId;
  String _selectedFolderName = 'Maplewood Receipts';
  bool _createNewSheet = true;
  String? _existingSheetId;
  String? _existingSheetName;
  bool _finishing = false;
  bool _detecting = false;
  bool _folderAutoDetected = false;
  bool _sheetAutoDetected = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (step == 3) _detectExisting();
  }

  // ── Step 2: Sign In ──

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _authError = null;
    });

    final success = await AuthService.signIn();

    if (!mounted) return;
    setState(() => _signingIn = false);

    if (success) {
      _goToStep(2);
    } else {
      setState(() => _authError = AuthService.lastError);
    }
  }

  // ── Step 3: Camera Permission ──

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _cameraDenied = false;
        _cameraPermanentlyDenied = false;
      });
      _goToStep(3);
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _cameraPermanentlyDenied = true;
        _cameraDenied = true;
      });
    } else {
      setState(() {
        _cameraDenied = true;
        _cameraPermanentlyDenied = false;
      });
    }
  }

  // ── Step 4: Combined Drive Setup ──

  Future<void> _detectExisting() async {
    setState(() => _detecting = true);
    try {
      final driveApi = await AuthService.getDriveApi();

      // Look for existing "Maplewood Receipts" folder
      final folderResult = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder'"
            " and name='Maplewood Receipts'"
            " and trashed=false",
        pageSize: 1,
        $fields: 'files(id, name)',
      );
      if (folderResult.files != null && folderResult.files!.isNotEmpty) {
        final folder = folderResult.files!.first;
        _selectedFolderId = folder.id;
        _selectedFolderName = folder.name ?? 'Maplewood Receipts';
        _createNewFolder = false;
        _folderAutoDetected = true;
      }

      // Look for existing "Maplewood Receipts" spreadsheet
      final sheetResult = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.spreadsheet'"
            " and name='Maplewood Receipts'"
            " and trashed=false",
        pageSize: 1,
        $fields: 'files(id, name)',
      );
      if (sheetResult.files != null && sheetResult.files!.isNotEmpty) {
        final sheet = sheetResult.files!.first;
        _existingSheetId = sheet.id;
        _existingSheetName = sheet.name ?? 'Maplewood Receipts';
        _createNewSheet = false;
        _sheetAutoDetected = true;
      }
    } catch (e) {
      // Detection failed silently — keep defaults (create new)
      print('Auto-detect error: $e');
    }
    if (mounted) setState(() => _detecting = false);
  }

  Future<void> _changeFolder() async {
    final result = await Navigator.of(context).push<FolderSelection>(
      MaterialPageRoute(builder: (_) => const DriveFolderPicker()),
    );
    if (result != null) {
      setState(() {
        _selectedFolderId = result.id;
        _selectedFolderName = result.name;
        _createNewFolder = false;
      });
    }
  }

  Future<void> _changeSheet() async {
    final result = await showModalBottomSheet<_SheetPick>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SpreadsheetPickerSheet(),
    );
    if (result != null && mounted) {
      setState(() {
        _createNewSheet = false;
        _existingSheetId = result.id;
        _existingSheetName = result.name;
      });
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      // Create folder if needed
      if (_createNewFolder) {
        final driveApi = await AuthService.getDriveApi();
        final folder = await driveApi.files.create(
          drive.File(
            name: 'Maplewood Receipts',
            mimeType: 'application/vnd.google-apps.folder',
            parents: ['root'],
          ),
          $fields: 'id',
        );
        _selectedFolderId = folder.id;
        _selectedFolderName = 'Maplewood Receipts';
      }
      await StorageService.setReceiptFolder(
          id: _selectedFolderId, name: _selectedFolderName);

      // Create spreadsheet if needed
      if (_createNewSheet) {
        await SheetsService.createSpreadsheet(
          name: 'Maplewood Receipts',
          folderId: _selectedFolderId,
        );
      } else if (_existingSheetId != null) {
        await SheetsService.setSpreadsheetId(_existingSheetId!);
      }

      // Mark onboarding complete
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);

      // Load sheet data + sync projects in background
      SheetCache.refresh().then((_) => ProjectService.syncWithCache());

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() => _finishing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: List.generate(4, (i) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: i <= _currentStep
                            ? Colors.blue
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomeStep(),
                  _buildSignInStep(),
                  _buildCameraStep(),
                  _buildDriveSetupStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: Welcome / How it works ──

  Widget _buildWelcomeStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(),
          const Text(
            'How Maplewood works',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          _buildFeatureRow(
            Icons.camera_alt,
            'Snap',
            'Take a photo of any receipt',
          ),
          const SizedBox(height: 20),
          _buildFeatureRow(
            Icons.auto_awesome,
            'Extract',
            'AI reads the vendor, date, and total',
          ),
          const SizedBox(height: 20),
          _buildFeatureRow(
            Icons.table_chart,
            'Track',
            'Data goes to a Google Sheet, photo goes to your Drive',
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: Colors.blue[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Everything stays in your Google account. Maplewood doesn\u2019t store your data.',
                    style: TextStyle(fontSize: 13, color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _goToStep(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Sounds good!', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.blue[600], size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2: Sign In ──

  Widget _buildSignInStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Icon(Icons.account_circle, size: 64, color: Colors.blue[400]),
          const SizedBox(height: 24),
          const Text(
            'Sign In',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Maplewood saves directly to your Google Drive and Sheets \u2014 sign in to connect your account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 48),
          if (_authError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[400], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_authError!,
                        style: TextStyle(color: Colors.red[700], fontSize: 14)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _signingIn ? null : _signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _signingIn
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Sign in with Google',
                      style: TextStyle(fontSize: 16)),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ── Step 3: Camera ──

  Widget _buildCameraStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Icon(Icons.camera_alt, size: 64, color: Colors.blue[400]),
          const SizedBox(height: 24),
          const Text(
            'Camera Access',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Maplewood uses your camera to scan and photograph receipts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 48),
          if (_cameraDenied) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _cameraPermanentlyDenied
                    ? 'Camera permission was denied. Please grant it in your device settings.'
                    : 'Camera permission is required to scan receipts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange[800], fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _cameraPermanentlyDenied ? openAppSettings : _requestCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _cameraPermanentlyDenied ? 'Open Settings' : 'Allow Camera',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          if (_cameraDenied && !_cameraPermanentlyDenied) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open Settings instead'),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  // ── Step 4: Combined Drive Setup ──

  Widget _buildDriveSetupStep() {
    final String folderLabel;
    if (_createNewFolder) {
      folderLabel = 'Maplewood Receipts (new folder)';
    } else if (_folderAutoDetected) {
      folderLabel = '$_selectedFolderName (automatically detected)';
    } else {
      folderLabel = _selectedFolderName;
    }
    final String sheetLabel;
    if (_createNewSheet) {
      sheetLabel = 'Maplewood Receipts (new spreadsheet)';
    } else if (_sheetAutoDetected) {
      sheetLabel = '${_existingSheetName ?? 'Maplewood Receipts'} (automatically detected)';
    } else {
      sheetLabel = _existingSheetName ?? 'Not set';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Set up your Drive',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Maplewood saves receipt photos to a Google Drive folder and tracks the data in a spreadsheet.',
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 28),

          // Photos folder
          _buildSetupRow(
            icon: Icons.folder,
            iconColor: Colors.amber[700]!,
            label: 'Photos folder',
            value: folderLabel,
            onChangeTap: _changeFolder,
          ),
          const SizedBox(height: 12),

          // Spreadsheet
          _buildSetupRow(
            icon: Icons.table_chart,
            iconColor: Colors.green[600]!,
            label: 'Receipt spreadsheet',
            value: sheetLabel,
            onChangeTap: _changeSheet,
          ),

          const SizedBox(height: 16),
          Text(
            'You can change these anytime in Settings.',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),

          const Spacer(),

          // Set it up
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: !_finishing && !_detecting ? _finish : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _finishing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Set it up',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required VoidCallback onChangeTap,
  }) {
    return Container(
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
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onChangeTap,
            child: Text('Change',
                style: TextStyle(color: Colors.blue[600], fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for picking an existing spreadsheet.
class _SpreadsheetPickerSheet extends StatefulWidget {
  const _SpreadsheetPickerSheet();

  @override
  State<_SpreadsheetPickerSheet> createState() =>
      _SpreadsheetPickerSheetState();
}

class _SpreadsheetPickerSheetState extends State<_SpreadsheetPickerSheet> {
  List<drive.File> _sheets = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final driveApi = await AuthService.getDriveApi();
      var q =
          "mimeType='application/vnd.google-apps.spreadsheet' and trashed=false";
      if (_query.isNotEmpty) {
        q += " and name contains '${_query.replaceAll("'", "\\'")}'";
      }
      final result = await driveApi.files.list(
        q: q,
        orderBy: 'modifiedTime desc',
        pageSize: 20,
        $fields: 'files(id, name)',
      );
      if (mounted) setState(() => _sheets = result.files ?? []);
    } catch (e) {
      // silently fail
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search spreadsheets...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) {
                _query = v.trim();
                _search();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sheets.isEmpty
                    ? Center(
                        child: Text('No spreadsheets found',
                            style: TextStyle(color: Colors.grey[500])))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _sheets.length,
                        itemBuilder: (context, index) {
                          final sheet = _sheets[index];
                          return ListTile(
                            leading:
                                Icon(Icons.table_chart, color: Colors.green[400]),
                            title: Text(sheet.name ?? 'Untitled'),
                            onTap: () => Navigator.pop(
                              context,
                              _SheetPick(
                                  id: sheet.id!, name: sheet.name ?? 'Untitled'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SheetPick {
  final String id;
  final String name;
  const _SheetPick({required this.id, required this.name});
}
