import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/gemini_service.dart';
import '../services/sheet_cache.dart';
import '../services/sheets_service.dart';
import '../services/project_service.dart';
import 'settings_screen.dart';

class ReviewScreen extends StatefulWidget {
  final ReceiptData receiptData;
  final String imageUrl;

  const ReviewScreen({
    super.key,
    required this.receiptData,
    required this.imageUrl,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late TextEditingController _vendorController;
  late TextEditingController _dateController;
  late TextEditingController _totalController;
  late TextEditingController _projectController;
  String? _selectedProject;
  List<String> _projects = [];
  bool _saving = false;
  bool _loadingProjects = true;
  String? _sheetName;
  List<Map<String, String>> _duplicates = [];

  @override
  void initState() {
    super.initState();
    _vendorController = TextEditingController(text: widget.receiptData.vendor);
    _dateController = TextEditingController(text: widget.receiptData.date ?? '');
    _totalController = TextEditingController(
        text: widget.receiptData.total?.toStringAsFixed(2) ?? '');
    _projectController = TextEditingController();
    _loadProjects();
    _loadSheetName();
    _checkDuplicates();
  }

  void _checkDuplicates() {
    // Runs against the local cache — no API call
    final dupes = SheetCache.findDuplicates(
      date: widget.receiptData.date ?? '',
      total: widget.receiptData.total,
    );
    setState(() => _duplicates = dupes);
  }

  void _showDuplicateModal() {
    showDialog(
      context: context,
      builder: (ctx) => _DuplicateModal(duplicates: _duplicates),
    );
  }

  Widget _modalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    fontSize: 13)),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Future<void> _loadProjects() async {
    final projects = await ProjectService.getProjects();
    setState(() {
      _projects = projects;
      if (projects.isNotEmpty) {
        _selectedProject = projects.first;
        _projectController.text = projects.first;
      }
      _loadingProjects = false;
    });
  }

  Future<void> _loadSheetName() async {
    final id = await SheetsService.getSpreadsheetId();
    if (id == null) return;
    try {
      final driveApi = await AuthService.getDriveApi();
      final file = await driveApi.files.get(id, $fields: 'name') as dynamic;
      if (mounted) setState(() => _sheetName = file.name ?? 'Untitled');
    } catch (_) {
      if (mounted) setState(() => _sheetName = 'Spreadsheet');
    }
  }

  Future<void> _confirm() async {
    final project = _projectController.text.trim();
    if (project.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter a project name')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await SheetsService.appendReceipt({
        Col.receiptNumber: widget.receiptData.receiptNumber,
        Col.project: project,
        Col.vendor: _vendorController.text,
        Col.totalCost: double.tryParse(_totalController.text) ?? '',
        Col.tax: widget.receiptData.tax ?? '',
        Col.receiptDate: _dateController.text,
        Col.inputDate: DateTime.now().toIso8601String(),
        Col.image: widget.imageUrl,
        Col.description: widget.receiptData.description ?? '',
      });

      // Mark project as recently used
      await ProjectService.markUsed(project);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt saved \u2713')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _vendorController.dispose();
    _dateController.dispose();
    _totalController.dispose();
    _projectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.grey[50],
        elevation: 0,
        title: GestureDetector(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            _loadSheetName();
            _loadProjects();
            _checkDuplicates();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.table_chart, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                _sheetName ?? '...',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: Colors.grey[600]),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadSheetName();
              _loadProjects();
              _checkDuplicates();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              // Duplicate warning
              if (_duplicates.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Material(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _showDuplicateModal,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _duplicates.length == 1
                                    ? 'Possible duplicate — tap to view'
                                    : '${_duplicates.length} possible duplicates — tap to view',
                                style: TextStyle(
                                    color: Colors.orange[900], fontSize: 13),
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                color: Colors.orange[400], size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Project Name
              const Text('Project:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _loadingProjects
                  ? const LinearProgressIndicator()
                  : Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) return _projects;
                        return _projects.where((p) => p
                            .toLowerCase()
                            .contains(textEditingValue.text.toLowerCase()));
                      },
                      initialValue: TextEditingValue(text: _selectedProject ?? ''),
                      onSelected: (value) {
                        _selectedProject = value;
                        _projectController.text = value;
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmitted) {
                        // Keep our controller in sync
                        controller.addListener(() {
                          _projectController.text = controller.text;
                        });
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            hintText: 'Select or type project name',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          onSubmitted: (_) => onSubmitted(),
                        );
                      },
                    ),

              const SizedBox(height: 24),

              // Vendor
              const Text('Vendor:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _vendorController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),

              const SizedBox(height: 24),

              // Date
              const Text('Date:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _dateController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  hintText: 'YYYY-MM-DD',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),

              const SizedBox(height: 24),

              // Cost Total
              const Text('Cost Total:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _totalController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  prefixText: '\$ ',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Confirm button (full width)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload, size: 28),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal that shows all duplicate matches with swipe pagination and embedded images.
class _DuplicateModal extends StatefulWidget {
  final List<Map<String, String>> duplicates;
  const _DuplicateModal({required this.duplicates});

  @override
  State<_DuplicateModal> createState() => _DuplicateModalState();
}

class _DuplicateModalState extends State<_DuplicateModal> {
  int _current = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    fontSize: 13)),
          ),
          Expanded(
              child: Text(value.isEmpty ? '\u2014' : value,
                  style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildPage(Map<String, String> r) {
    final imageLink = r[Col.image] ?? '';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Project', r[Col.project] ?? ''),
          _row('Vendor', r[Col.vendor] ?? ''),
          _row('Date', r[Col.receiptDate] ?? ''),
          _row('Total', '\$${r[Col.totalCost] ?? ''}'),
          _row('Tax',
              (r[Col.tax] ?? '').isNotEmpty ? '\$${r[Col.tax]}' : '\u2014'),
          _row('Added', r[Col.inputDate] ?? ''),
          if (imageLink.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageLink,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 220,
                        child: Center(
                            child:
                                CircularProgressIndicator(strokeWidth: 2))),
                errorBuilder: (_, _, _) => InkWell(
                  onTap: () => launchUrl(Uri.parse(imageLink),
                      mode: LaunchMode.externalApplication),
                  child: Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Icon(Icons.image, size: 18, color: Colors.blue[600]),
                        const SizedBox(width: 6),
                        Text('Open image',
                            style: TextStyle(
                                color: Colors.blue[600],
                                decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => launchUrl(Uri.parse(imageLink),
                    mode: LaunchMode.externalApplication),
                child: Text('Open full size',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[600],
                        decoration: TextDecoration.underline)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.duplicates.length;
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Possible Duplicate')),
          if (count > 1)
            Text('${_current + 1}/$count',
                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: count == 1
            ? _buildPage(widget.duplicates.first)
            : PageView.builder(
                controller: _pageController,
                itemCount: count,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (_, i) => _buildPage(widget.duplicates[i]),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
