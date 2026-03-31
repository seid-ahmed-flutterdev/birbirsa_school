import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../core/app_colors.dart';
import '../widgets/glass_card.dart';

// ─────────────────────────────────────────────────────────────
//  CONTENT PREVIEW PAGE
//
//  Displaying images, video, audio, and pdf directly in the app.
// ─────────────────────────────────────────────────────────────

class ContentPreviewPage extends StatefulWidget {
  final Map<String, dynamic> item;

  const ContentPreviewPage({super.key, required this.item});

  @override
  State<ContentPreviewPage> createState() => _ContentPreviewPageState();
}

class _ContentPreviewPageState extends State<ContentPreviewPage> {
  @override
  void initState() {
    super.initState();
  }

  /// Make any URL absolute
  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (kIsWeb) {
      return '${Uri.base.origin}$url';
    }
    return 'http://localhost:3000$url';
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = widget.item['url'] as String?;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.item['title'] ?? 'Preview',
          style: const TextStyle(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (rawUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new, color: AppColors.highlight),
              onPressed: () {
                final absUrl = _resolveUrl(rawUrl);
                launchUrl(
                  Uri.parse(absUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
              tooltip: 'Open in Browser',
            ),
        ],
      ),
      body: Center(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final type = widget.item['type'];
    final rawUrl = widget.item['url'] as String?;
    final absUrl = rawUrl != null ? _resolveUrl(rawUrl) : null;

    if (absUrl == null && type != 'text') {
      return _noContentWidget();
    }

    switch (type) {
      case 'image':
        return InteractiveViewer(
          minScale: 0.1,
          maxScale: 5.0,
          child: Center(
            child: Image.network(
              absUrl!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.highlight),
                );
              },
              errorBuilder: (context, error, stack) => _errorWidget('image'),
            ),
          ),
        );

      case 'pdf':
        if (kIsWeb) {
          // On Web, use a direct browser approach for the best experience
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.picture_as_pdf,
                size: 100,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 24),
              const Text(
                'PDF Ready',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Opening file directly in browser...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(absUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text(
                  'Open PDF Directly',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.highlight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ],
          );
        }
        return SfPdfViewer.network(
          absUrl!,
          canShowScrollHead: false,
          canShowScrollStatus: false,
        );

      case 'video':
        return _VideoPlayerView(url: absUrl!);

      case 'audio':
        return _AudioPlayerView(url: absUrl!);

      case 'doc':
        return _downloadWidget(absUrl, 'Document');

      case 'text':
      default:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.campaign, size: 60, color: AppColors.highlight),
              const SizedBox(height: 30),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: GlassCard(
                  child: Text(
                    widget.item['title'] ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _downloadWidget(String? absUrl, String fileType) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.description, size: 80, color: Colors.blueAccent),
        const SizedBox(height: 20),
        Text(
          widget.item['title'] ?? fileType,
          style: const TextStyle(color: Colors.white, fontSize: 20),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(fileType, style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 30),
        if (absUrl != null)
          ElevatedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(absUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.download),
            label: Text('Download $fileType'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.highlight,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _noContentWidget() {
    return const Center(
      child: Text(
        'No content available',
        style: TextStyle(color: Colors.white54),
      ),
    );
  }

  Widget _errorWidget(String type) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, size: 80, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            'Could not load $type.\nCheck server connection.',
            style: const TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// VIDEO PLAYER WIDGET
// ─────────────────────────────────────────────────────────────
class _VideoPlayerView extends StatefulWidget {
  final String url;
  const _VideoPlayerView({required this.url});

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      await _videoPlayerController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        allowPlaybackSpeedChanging: false,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Video error: $e");
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
        child: Text(
          'Error loading video',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    if (_chewieController != null &&
        _chewieController!.videoPlayerController.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    }
    return const Center(
      child: CircularProgressIndicator(color: AppColors.highlight),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AUDIO PLAYER WIDGET
// ─────────────────────────────────────────────────────────────
class _AudioPlayerView extends StatefulWidget {
  final String url;
  const _AudioPlayerView({required this.url});

  @override
  State<_AudioPlayerView> createState() => _AudioPlayerViewState();
}

class _AudioPlayerViewState extends State<_AudioPlayerView> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) {
        setState(() {
          _duration = newDuration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) {
        setState(() {
          _position = newPosition;
        });
      }
    });

    _audioPlayer.setSourceUrl(widget.url);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.audiotrack,
                    size: 80,
                    color: AppColors.highlight,
                  ),
                  const SizedBox(height: 32),
                  Slider(
                    value: _position.inSeconds.toDouble().clamp(
                      0.0,
                      _duration.inSeconds.toDouble() > 0
                          ? _duration.inSeconds.toDouble()
                          : 1.0,
                    ),
                    min: 0.0,
                    max: _duration.inSeconds.toDouble() > 0
                        ? _duration.inSeconds.toDouble()
                        : 1.0,
                    activeColor: AppColors.highlight,
                    inactiveColor: Colors.white24,
                    onChanged: (val) {
                      _audioPlayer.seek(Duration(seconds: val.toInt()));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.highlight,
                    child: IconButton(
                      iconSize: 36,
                      color: Colors.white,
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: () {
                        if (_isPlaying) {
                          _audioPlayer.pause();
                        } else {
                          _audioPlayer.play(UrlSource(widget.url));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
