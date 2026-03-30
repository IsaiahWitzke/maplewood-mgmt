import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/auth_service.dart';

/// Result returned by the folder picker.
class FolderSelection {
  final String? id; // null = Drive root
  final String name;
  const FolderSelection({this.id, required this.name});
}

/// A full-screen folder picker that lets the user navigate into nested
/// Google Drive folders and select one.
class DriveFolderPicker extends StatefulWidget {
  /// Optional: pre-select a folder when opening.
  final String? initialFolderId;
  final String? initialFolderName;

  const DriveFolderPicker({super.key, this.initialFolderId, this.initialFolderName});

  @override
  State<DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<DriveFolderPicker> {
  // Breadcrumb stack: each entry is (id, name). First is always root.
  final List<_BreadcrumbEntry> _stack = [];
  List<drive.File> _folders = [];
  bool _loading = true;
  String? _error;

  String get _currentName => _stack.isEmpty ? 'My Drive' : _stack.last.name;

  @override
  void initState() {
    super.initState();
    _loadFolders('root');
  }

  Future<void> _loadFolders(String parentId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final driveApi = await AuthService.getDriveApi();
      final result = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and '$parentId' in parents and trashed=false",
        orderBy: 'name',
        pageSize: 100,
        $fields: 'files(id, name)',
      );
      setState(() {
        _folders = result.files ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigateInto(drive.File folder) {
    _stack.add(_BreadcrumbEntry(id: folder.id!, name: folder.name ?? 'Untitled'));
    _loadFolders(folder.id!);
  }

  void _navigateTo(int index) {
    // index -1 = root, 0 = first folder, etc.
    if (index < 0) {
      _stack.clear();
      _loadFolders('root');
    } else {
      final targetId = _stack[index].id;
      _stack.removeRange(index + 1, _stack.length);
      _loadFolders(targetId);
    }
  }

  Future<void> _createFolder() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    setState(() => _loading = true);
    try {
      final driveApi = await AuthService.getDriveApi();
      final parentId = _stack.isEmpty ? 'root' : _stack.last.id;
      final created = await driveApi.files.create(
        drive.File(
          name: name,
          mimeType: 'application/vnd.google-apps.folder',
          parents: [parentId],
        ),
        $fields: 'id, name',
      );
      // Navigate into the new folder
      _navigateInto(created);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating folder: $e')),
        );
      }
    }
  }

  void _selectCurrent() {
    Navigator.of(context).pop(FolderSelection(
      id: _stack.isEmpty ? null : _stack.last.id,
      name: _currentName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.grey[50],
        elevation: 0,
        title: const Text('Choose Folder'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'New folder',
            onPressed: _loading ? null : _createFolder,
          ),
        ],
      ),
      body: Column(
        children: [
          // Breadcrumb trail
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true, // keep rightmost (current) visible
              child: Row(
                children: [
                  _buildBreadcrumb('My Drive', -1),
                  for (var i = 0; i < _stack.length; i++) ...[
                    Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
                    _buildBreadcrumb(_stack[i].name, i),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Folder list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Error loading folders:\n$_error',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red[400])),
                        ),
                      )
                    : _folders.isEmpty
                        ? Center(
                            child: Text('No subfolders',
                                style: TextStyle(color: Colors.grey[500])),
                          )
                        : ListView.builder(
                            itemCount: _folders.length,
                            itemBuilder: (context, index) {
                              final folder = _folders[index];
                              return ListTile(
                                leading: Icon(Icons.folder, color: Colors.amber[700]),
                                title: Text(folder.name ?? 'Untitled'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _navigateInto(folder),
                              );
                            },
                          ),
          ),

          // Select button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _selectCurrent,
                  icon: const Icon(Icons.check),
                  label: Text('Select "$_currentName"'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(String name, int index) {
    final isCurrent = (index == -1 && _stack.isEmpty) || (index == _stack.length - 1);
    return GestureDetector(
      onTap: isCurrent ? null : () => _navigateTo(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 14,
            color: isCurrent ? Colors.black87 : Colors.blue,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbEntry {
  final String id;
  final String name;
  const _BreadcrumbEntry({required this.id, required this.name});
}
