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

  // Step 1: Auth
  bool _signingIn = false;
  String? _authError;

  // Step 2: Camera
  bool _cameraDenied = false;
  bool _cameraPermanentlyDenied = false;

  // Step 3: Folder
  List<drive.File> _rootFolders = [];
  bool _loadingFolders = true;
  String? _selectedFolderId;
  String _selectedFolderName = '';
  bool _createNewFolder = true; // default: create "Maplewood Receipts"
  bool _creatingFolder = false;

  // Step 4: Spreadsheet
  bool _createNewSheet = true;
  final _sheetNameController =
      TextEditingController(text: 'Maplewood Receipts');
  String? _existingSheetId;
  String? _existingSheetName;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    _sheetNameController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ── Step 1: Sign In ──

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _authError = null;
    });

    final success = await AuthService.signIn();

    if (!mounted) return;
    setState(() => _signingIn = false);

    if (success) {
      _goToStep(1);
    } else if (AuthService.currentUser == null) {
      // User cancelled or error — only show error if it wasn't a cancel
      // signIn returns false for both cancel and error, so we keep it subtle
      setState(() => _authError = null); // silent on cancel
    }
  }

  // ── Step 2: Camera Permission ──

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _cameraDenied = false;
        _cameraPermanentlyDenied = false;
      });
      _loadRootFolders();
      _goToStep(2);
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

  // ── Step 3: Folder ──

  Future<void> _loadRootFolders() async {
    setState(() => _loadingFolders = true);
    try {
      final driveApi = await AuthService.getDriveApi();
      final result = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and 'root' in parents and trashed=false",
        orderBy: 'modifiedTime desc',
        pageSize: 4,
        $fields: 'files(id, name)',
      );
      if (mounted) {
        setState(() {
          _rootFolders = result.files ?? [];
          _loadingFolders = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingFolders = false);
    }
  }

  void _selectFolder(String? id, String name, {bool isNew = false}) {
    setState(() {
      _selectedFolderId = id;
      _selectedFolderName = name;
      _createNewFolder = isNew;
    });
  }

  Future<void> _confirmFolder() async {
    if (_createNewFolder) {
      // Create the folder in Drive
      setState(() => _creatingFolder = true);
      try {
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
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating folder: $e')),
          );
        }
        setState(() => _creatingFolder = false);
        return;
      }
      setState(() => _creatingFolder = false);
    }

    await StorageService.setReceiptFolder(
        id: _selectedFolderId, name: _selectedFolderName);
    _goToStep(3);
  }

  Future<void> _browseForFolder() async {
    final result = await Navigator.of(context).push<FolderSelection>(
      MaterialPageRoute(builder: (_) => const DriveFolderPicker()),
    );
    if (result != null) {
      _selectFolder(result.id, result.name, isNew: false);
    }
  }

  // ── Step 4: Spreadsheet ──

  Future<void> _pickExistingSheet() async {
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
      if (_createNewSheet) {
        await SheetsService.createSpreadsheet(
          name: _sheetNameController.text.trim().isEmpty
              ? 'Maplewood Receipts'
              : _sheetNameController.text.trim(),
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
                  _buildSignInStep(),
                  _buildCameraStep(),
                  _buildFolderStep(),
                  _buildSheetStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1 UI ──

  Widget _buildSignInStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Icon(Icons.receipt_long, size: 64, color: Colors.blue[400]),
          const SizedBox(height: 24),
          const Text(
            'Welcome to Maplewood',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Construction receipt management',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
          const SizedBox(height: 12),
          Text(
            'Required for Google Drive & Sheets access',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ── Step 2 UI ──

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

  // ── Step 3 UI ──

  Widget _buildFolderStep() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Receipt Images',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a Google Drive folder for your receipt photos.',
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: _loadingFolders
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      // Create new option
                      _buildFolderTile(
                        icon: Icons.create_new_folder,
                        iconColor: Colors.blue,
                        title: 'Maplewood Receipts',
                        subtitle: 'Create new folder in My Drive',
                        selected: _createNewFolder,
                        onTap: () =>
                            _selectFolder(null, 'Maplewood Receipts', isNew: true),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Or choose an existing folder:',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[500])),
                      ),

                      // Root folders
                      ..._rootFolders.map((f) => _buildFolderTile(
                            icon: Icons.folder,
                            iconColor: Colors.amber[700]!,
                            title: f.name ?? 'Untitled',
                            selected: !_createNewFolder &&
                                _selectedFolderId == f.id,
                            onTap: () => _selectFolder(
                                f.id, f.name ?? 'Untitled',
                                isNew: false),
                          )),

                      // Browse / create option
                      _buildFolderTile(
                        icon: Icons.more_horiz,
                        iconColor: Colors.grey,
                        title: 'Browse or create...',
                        subtitle: 'Find another folder or create a new one',
                        selected: false,
                        onTap: _browseForFolder,
                        showChevron: true,
                      ),
                    ],
                  ),
          ),

          // Continue button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_createNewFolder ||
                      _selectedFolderId != null) &&
                  !_creatingFolder
                  ? _confirmFolder
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _creatingFolder
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Continue', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
    bool showChevron = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? Colors.blue : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        tileColor: selected ? Colors.blue[50] : Colors.white,
        leading: Icon(icon, color: iconColor),
        title: Text(title),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]))
            : null,
        trailing: selected
            ? Icon(Icons.check_circle, color: Colors.blue[600])
            : showChevron
                ? const Icon(Icons.chevron_right)
                : null,
        onTap: onTap,
      ),
    );
  }

  // ── Step 4 UI ──

  Widget _buildSheetStep() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spreadsheet',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Where should extracted receipt data be saved?',
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // Option 1: Create new
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: _createNewSheet ? Colors.blue : Colors.grey[300]!,
                width: _createNewSheet ? 2 : 1,
              ),
            ),
            tileColor: _createNewSheet ? Colors.blue[50] : Colors.white,
            leading: Icon(Icons.add_circle_outline,
                color: _createNewSheet ? Colors.blue[600] : Colors.grey),
            title: const Text('Create new spreadsheet'),
            subtitle: Text('In $_selectedFolderName',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            trailing: _createNewSheet
                ? Icon(Icons.check_circle, color: Colors.blue[600])
                : null,
            onTap: () => setState(() => _createNewSheet = true),
          ),

          if (_createNewSheet) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _sheetNameController,
              decoration: InputDecoration(
                labelText: 'Spreadsheet name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Option 2: Choose existing
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: !_createNewSheet ? Colors.blue : Colors.grey[300]!,
                width: !_createNewSheet ? 2 : 1,
              ),
            ),
            tileColor: !_createNewSheet ? Colors.blue[50] : Colors.white,
            leading: Icon(Icons.table_chart,
                color: !_createNewSheet ? Colors.blue[600] : Colors.grey),
            title: const Text('Use existing spreadsheet'),
            subtitle: _existingSheetName != null
                ? Text(_existingSheetName!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]))
                : null,
            trailing: !_createNewSheet
                ? Icon(Icons.check_circle, color: Colors.blue[600])
                : const Icon(Icons.chevron_right),
            onTap: _pickExistingSheet,
          ),

          const Spacer(),

          // Get Started
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_createNewSheet || _existingSheetId != null) &&
                      !_finishing
                  ? _finish
                  : null,
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
                  : const Text('Get Started',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
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
