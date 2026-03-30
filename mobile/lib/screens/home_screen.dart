import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/gemini_service.dart';
import '../services/sheet_cache.dart';
import '../services/storage_service.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

enum ProcessingStatus { idle, processing, success, failed }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  ProcessingStatus _status = ProcessingStatus.idle;
  String _message = 'Ready to scan receipts';
  final List<ProcessingStatus> _recentStatuses = [];
  String? _capturedImagePath; // Freeze the captured photo on screen

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _message = 'No camera found');
      return;
    }

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.setFocusMode(FocusMode.auto);
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      setState(() => _message = 'Camera error: $e');
    }
  }

  Future<void> _captureReceipt() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      final photo = await _cameraController!.takePicture();

      setState(() {
        _capturedImagePath = photo.path;
        _status = ProcessingStatus.processing;
        _message = 'Processing receipt...';
        _recentStatuses.insert(0, ProcessingStatus.processing);
        if (_recentStatuses.length > 5) _recentStatuses.removeLast();
      });

      final imageBytes = await photo.readAsBytes();

      // Sync cache in background (don't block capture)
      SheetCache.sync();

      // Upload image and run OCR in parallel
      final results = await Future.wait([
        StorageService.uploadReceiptImage(imageBytes),
        GeminiService.extractReceipt(imageBytes),
      ]);

      final imageUrl = results[0] as String;
      final receiptData = results[1] as ReceiptData;

      setState(() {
        _status = ProcessingStatus.success;
        _message = 'Receipt processed ✓';
        _recentStatuses[0] = ProcessingStatus.success;
      });

      if (mounted) {
        setState(() {
          _capturedImagePath = null;
          _status = ProcessingStatus.idle;
          _message = '';
        });
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReviewScreen(
              receiptData: receiptData,
              imageUrl: imageUrl,
            ),
          ),
        );
      }
    } catch (e) {
      print('Receipt processing error: $e');
      setState(() {
        _status = ProcessingStatus.failed;
        final msg = e.toString();
        _message = 'Failed: ${msg.length > 120 ? '${msg.substring(0, 120)}...' : msg}';
        if (_recentStatuses.isNotEmpty) _recentStatuses[0] = ProcessingStatus.failed;
        _capturedImagePath = null;
      });
    }
  }

  Color _statusColor(ProcessingStatus status) {
    switch (status) {
      case ProcessingStatus.idle:
        return Colors.grey;
      case ProcessingStatus.processing:
        return Colors.amber;
      case ProcessingStatus.success:
        return Colors.green;
      case ProcessingStatus.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _status == ProcessingStatus.processing ? null : _captureReceipt,
        child: Stack(
          children: [
            // Show frozen capture or live preview
            if (_capturedImagePath != null)
              Positioned.fill(
                child: Image.file(
                  File(_capturedImagePath!),
                  fit: BoxFit.cover,
                ),
              )
            else if (_isCameraReady && _cameraController != null)
              Positioned.fill(
                child: CameraPreview(_cameraController!),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Settings icon (top right)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(120),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),

            // Bottom status bar - only shows when there's something to communicate
            if (_status != ProcessingStatus.idle)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _status = ProcessingStatus.idle;
                      _message = '';
                    }),
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    child: Row(
                      children: [
                        // Status dot
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _statusColor(_status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Message
                        Expanded(
                          child: Text(
                            _message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        // Spinner while processing
                        if (_status == ProcessingStatus.processing)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.amber,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
