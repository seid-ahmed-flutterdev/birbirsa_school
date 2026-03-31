import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../core/app_colors.dart';
import '../widgets/glass_card.dart';

class WebCameraCapture extends StatefulWidget {
  const WebCameraCapture({super.key});

  @override
  State<WebCameraCapture> createState() => _WebCameraCaptureState();
}

class _WebCameraCaptureState extends State<WebCameraCapture> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _controller!.initialize();
        if (mounted) {
          setState(() => _isInitialized = true);
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Camera Capture',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 400,
                height: 300,
                child: CameraPreview(_controller!),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  onPressed: () async {
                    final XFile photo = await _controller!.takePicture();
                    final bytes = await photo.readAsBytes();
                    if (mounted) {
                      Navigator.pop(context, {
                        'name': photo.name,
                        'bytes': bytes,
                      });
                    }
                  },
                  icon: const Icon(Icons.camera),
                  label: const Text('Capture'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.highlight,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
