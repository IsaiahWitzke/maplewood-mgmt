import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/auth_service.dart';
import '../services/sheets_service.dart';
import '../services/project_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final List<drive.File> _spreadsheets = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _creating = false;
  String? _currentId;
  String? _nextPageToken;
  String _searchQuery = '';
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _nextPageToken != null) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _spreadsheets.clear();
      _nextPageToken = null;
    });
    try {
      _currentId = await SheetsService.getSpreadsheetId();
      await _fetchPage();
    } catch (e) {
      print('Error loading spreadsheets: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextPageToken == null) return;
    setState(() => _loadingMore = true);
    try {
      await _fetchPage();
    } catch (e) {
      print('Error loading more: $e');
    }
    setState(() => _loadingMore = false);
  }

  Future<void> _fetchPage() async {
    final driveApi = await AuthService.getDriveApi();
    var query = "mimeType='application/vnd.google-apps.spreadsheet' and trashed=false";
    if (_searchQuery.isNotEmpty) {
      query += " and name contains '${_searchQuery.replaceAll("'", "\\'")}'";
    }
    final result = await driveApi.files.list(
      q: query,
      orderBy: 'modifiedTime desc',
      pageSize: 20,
      pageToken: _nextPageToken,
      $fields: 'nextPageToken, files(id, name, modifiedTime)',
    );
    setState(() {
      _spreadsheets.addAll(result.files ?? []);
      _nextPageToken = result.nextPageToken;
    });
  }

  void _onSearchChanged(String value) {
    _searchQuery = value.trim();
    _load();
  }

  Future<void> _select(String id, String name) async {
    await SheetsService.setSpreadsheetId(id);
    await ProjectService.clear();
    ProjectService.syncWithSheet(); // fire and forget
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Using "$name" \u2713')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController(text: 'Maplewood Receipts');
    String? selectedFolderId;
    String selectedFolderName = 'My Drive (root)';
    List<drive.File>? folders;

    // Fetch folders
    try {
      final driveApi = await AuthService.getDriveApi();
      final result = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and trashed=false",
        orderBy: 'name',
        pageSize: 100,
        $fields: 'files(id, name)',
      );
      folders = result.files;
    } catch (e) {
      print('Error loading folders: $e');
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Spreadsheet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Text('Location', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDialog<drive.File>(
                    context: ctx,
                    builder: (_) => _FolderPickerDialog(folders: folders ?? []),
                  );
                  if (picked != null) {
                    setDialogState(() {
                      selectedFolderId = picked.id;
                      selectedFolderName = picked.name ?? 'Untitled';
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder, size: 20, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(child: Text(selectedFolderName)),
                      Icon(Icons.chevron_right, color: Colors.grey[400]),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _creating = true);
    try {
      await SheetsService.createSpreadsheet(
        name: nameController.text.trim(),
        folderId: selectedFolderId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spreadsheet created \u2713')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _creating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Select Spreadsheet'),
        backgroundColor: Colors.grey[50],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _creating ? null : _showCreateDialog,
            tooltip: 'Create new spreadsheet',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search spreadsheets...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: Colors.white,
              ),
              controller: _searchController,
              onChanged: _onSearchChanged,
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _spreadsheets.isEmpty
                    ? Center(
                        child: Text('No spreadsheets found',
                            style: TextStyle(color: Colors.grey[500])))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _spreadsheets.length + (_nextPageToken != null ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _spreadsheets.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          }
                          final file = _spreadsheets[index];
                          final isSelected = file.id == _currentId;
                          return ListTile(
                            leading: Icon(
                              Icons.table_chart,
                              color: isSelected
                                  ? Colors.green[600]
                                  : Colors.green[300],
                            ),
                            title: Text(
                              file.name ?? 'Untitled',
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: file.modifiedTime != null
                                ? Text(
                                    'Modified ${_timeAgo(file.modifiedTime!)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500]),
                                  )
                                : null,
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: Colors.green[600])
                                : const Icon(Icons.chevron_right),
                            onTap: () => _select(file.id!, file.name ?? 'Untitled'),
                          );
                        },
                      ),
          ),

        ],
      ),
    );
  }
}

class _FolderPickerDialog extends StatelessWidget {
  final List<drive.File> folders;
  const _FolderPickerDialog({required this.folders});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose folder'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.grey),
              title: const Text('My Drive (root)'),
              onTap: () => Navigator.pop(context, drive.File()..name = 'My Drive (root)'),
            ),
            ...folders.map((f) => ListTile(
              leading: Icon(Icons.folder, color: Colors.amber[700]),
              title: Text(f.name ?? 'Untitled'),
              onTap: () => Navigator.pop(context, f),
            )),
          ],
        ),
      ),
    );
  }
}
