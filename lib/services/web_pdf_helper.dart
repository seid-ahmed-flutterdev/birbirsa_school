// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

/// Makes a URL absolute if it's relative (for use in iframe/img src)
/// On web, window.location gives us the current origin
String _makeAbsolute(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  // Relative URL — prepend current origin
  final origin = html.window.location.origin ?? '';
  return '$origin$url';
}

/// Open any file URL in a new browser tab — the PERMANENT solution.
/// The browser natively handles PDFs, images, video, audio, docs.
/// This replaces all the HtmlElementView approaches that kept breaking.
void openInNewTab(String url) {
  final absoluteUrl = _makeAbsolute(url);
  html.window.open(absoluteUrl, '_blank');
}

/// Register a PDF viewer using iframe — kept for backward compatibility
/// but the preferred approach is now openInNewTab()
void registerPdfView(String viewId, String url) {
  final absoluteUrl = _makeAbsolute(url);
  try {
    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int viewId) => html.IFrameElement()
        ..src = absoluteUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allowfullscreen', 'true'),
    );
  } catch (e) {
    // View ID already registered — ignore (prevents crash on re-navigation)
    print('registerPdfView: $e');
  }
}

/// Register an image viewer — kept for backward compatibility
void registerImageView(String viewId, String url) {
  final absoluteUrl = _makeAbsolute(url);
  try {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
      final container = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'flex'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.backgroundColor = 'black';

      final img = html.ImageElement()
        ..src = absoluteUrl
        ..style.maxWidth = '100%'
        ..style.maxHeight = '100%'
        ..style.objectFit = 'contain'
        ..style.border = 'none';

      container.append(img);
      return container;
    });
  } catch (e) {
    print('registerImageView: $e');
  }
}

/// Register a native HTML5 video player — kept for backward compatibility
void registerVideoView(String viewId, String url) {
  final absoluteUrl = _makeAbsolute(url);
  try {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
      final video = html.VideoElement()
        ..src = absoluteUrl
        ..controls = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = 'black'
        ..style.border = 'none';
      video.setAttribute('playsinline', 'true');
      video.setAttribute('preload', 'metadata');
      return video;
    });
  } catch (e) {
    print('registerVideoView: $e');
  }
}

/// Register a native HTML5 audio player — kept for backward compatibility
void registerAudioView(String viewId, String url) {
  final absoluteUrl = _makeAbsolute(url);
  try {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
      final container = html.DivElement()
        ..style.display = 'flex'
        ..style.flexDirection = 'column'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = 'transparent';

      final audio = html.AudioElement()
        ..src = absoluteUrl
        ..controls = true
        ..style.width = '90%'
        ..style.maxWidth = '500px';

      container.append(audio);
      return container;
    });
  } catch (e) {
    print('registerAudioView: $e');
  }
}
