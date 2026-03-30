import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
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
    // We don't have the sheet name stored, just show the ID truncated
    final id = await SheetsService.getSpreadsheetId();
    if (id != null && mounted) {
      setState(() {
        _sheetName = id.length > 20 ? '${id.substring(0, 20)}...' : id;
      });
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
      await SheetsService.appendReceipt(
        receiptNumber: widget.receiptData.receiptNumber,
        project: project,
        vendor: _vendorController.text,
        total: double.tryParse(_totalController.text),
        tax: widget.receiptData.tax,
        receiptDate: _dateController.text,
        imageLink: widget.imageUrl,
      );

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
            _loadSheetName(); // Refresh after potential switch
            _loadProjects();
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
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

              const Spacer(),

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
                      : const Text('GO',
                          style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
