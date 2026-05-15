import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';

class TelegramService {
  static const String bot1Token =
      '8363076420:AAEZ78VfLhgjLBFlzAEjvqf1jt10A30TPGU'; // Registration & Payment
  static const String bot2Token =
      '8704157930:AAE8Q1Y_dKgIjPbdOBetsefPGAokNJLLoZo'; // Advert & Rules
  static const String chatId = '8319751158'; // Director's Chat ID

  // Backend URL — always absolute so http.post/get resolves correctly on any device
  // Backend URL from configuration
  static String get _origin => ApiConfig.baseUrl;

  static String get backendUrl => ApiConfig.contentUrl;
  static String get _proxyUrl => ApiConfig.proxyUrl;

  /// Wake Render free-tier backend before important API calls (cold start ~30–50s).
  static Future<bool> ensureBackendAwake() async {
    final healthUrl = Uri.parse(ApiConfig.healthUrl);
    for (int attempt = 0; attempt < 4; attempt++) {
      try {
        final timeout = attempt == 0
            ? const Duration(seconds: 60)
            : const Duration(seconds: 30);
        final res = await http.get(healthUrl).timeout(timeout);
        if (res.statusCode == 200) {
          debugPrint('✅ Backend awake (attempt ${attempt + 1})');
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ Backend wake attempt ${attempt + 1}: $e');
      }
      if (attempt < 3) {
        await Future.delayed(Duration(seconds: 4 * (attempt + 1)));
      }
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  //  DIRECT TELEGRAM URL CACHE
  //  Resolves file_id → direct https://api.telegram.org/file/...
  //  These URLs work from ANY device, ANY network, NO server needed.
  //  Cache expires after 50 minutes (Telegram URLs last ~1 hour).
  // ─────────────────────────────────────────────────────────────
  static final Map<String, _CachedUrl> _directUrlCache = {};

  /// Get a direct Telegram download URL for a file_id.
  static Future<String?> getDirectFileUrl(String fileId) async {
    final cached = _directUrlCache[fileId];
    if (cached != null && !cached.isExpired) return cached.url;
    try {
      final res = await http
          .get(
            Uri.parse(
              'https://api.telegram.org/bot$bot2Token/getFile?file_id=$fileId',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['ok'] == true) {
          final filePath = data['result']['file_path'] as String;
          final url = 'https://api.telegram.org/file/bot$bot2Token/$filePath';
          _directUrlCache[fileId] = _CachedUrl(url);
          return url;
        }
      }
    } catch (e) {
      debugPrint('Error resolving direct file URL: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  //  REGISTRATION — server handles save + Telegram notification + photos
  // ─────────────────────────────────────────────────────────────
  static Future<bool> sendRegistration({
    required String fullName,
    required String fatherName,
    required String motherName,
    required String phoneNumber,
    required String grade,
    required String section,
    String? stream,
    List<Map<String, dynamic>>? files,
  }) async {
    final regId =
        'BR${(100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString()}';

    final message =
        '🎯 NEW REGISTRATION\n\n'
        '🆔 ID: $regId\n'
        '👤 Student: $fullName\n'
        '🎓 Grade: Grade $grade\n'
        '📚 Section: $section\n'
        '📞 Phone: $phoneNumber\n'
        '👨 Father: $fatherName\n'
        '👩 Mother: $motherName\n'
        '${stream != null ? "🧬 Stream: $stream\n" : ""}';

    // ── Server handles save + Telegram with SAVE button (responds in <1s) ──
    final serverOk = await _notifyServerWithFiles(
      name: fullName,
      phone: phoneNumber,
      regId: regId,
      details: message,
      type: 'registration',
      files: files,
    );

    if (!serverOk) {
      await _sendTelegramDirectly(
        message: message,
        files: files,
        note:
            '⚠️ Server was sleeping — record may not appear in School Bot search yet. '
            'Director: ask student to submit again in 1 minute, or search after server wakes.',
      );
    }

    return serverOk;
  }

  // ─────────────────────────────────────────────────────────────
  //  PAYMENT — server handles save + Telegram notification + photos
  // ─────────────────────────────────────────────────────────────
  static Future<bool> sendPayment({
    required String fullName,
    required String phoneNumber,
    required String grade,
    required String section,
    String? stream,
    required List<Map<String, dynamic>> receipts,
  }) async {
    final payId =
        'PAY${(100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString()}';

    final message =
        '💸 NEW FEE PAYMENT\n\n'
        '🆔 ID: $payId\n'
        '👤 Student: $fullName\n'
        '🎓 Grade: Grade $grade\n'
        '📚 Section: $section\n'
        '📞 Phone: $phoneNumber\n'
        '${stream != null ? "🧬 Stream: $stream\n" : ""}';

    final serverOk = await _notifyServerWithFiles(
      name: fullName,
      phone: phoneNumber,
      regId: payId,
      details: message,
      type: 'payment',
      files: receipts,
    );

    if (!serverOk) {
      await _sendTelegramDirectly(
        message: message,
        files: receipts,
        note:
            '⚠️ Server was sleeping — payment may not appear in School Bot search yet. '
            'Director: ask family to submit again in 1 minute if needed.',
      );
    }

    return serverOk;
  }

  // ─────────────────────────────────────────────────────────────
  //  NOTIFY SERVER WITH FILES (multipart)
  //  Server saves photos+docs to disk, sends Telegram with SAVE button.
  // ─────────────────────────────────────────────────────────────
  static Future<bool> _notifyServerWithFiles({
    required String name,
    required String phone,
    required String regId,
    required String details,
    required String type,
    List<Map<String, dynamic>>? files,
  }) async {
    await ensureBackendAwake();

    final notifyUrl = Uri.parse('$_origin/api/notify-registration');
    final allFiles = files ?? [];
    final images = allFiles.where(_isImage).toList();
    final docs = allFiles.where((f) => !_isImage(f)).toList();
    final hasFiles = images.isNotEmpty || docs.isNotEmpty;

    final payload = jsonEncode({
      'name': name,
      'phone': phone,
      'reg_id': regId,
      'details': details,
      'type': type,
    });

    try {
      if (!hasFiles) {
        for (int attempt = 0; attempt < 4; attempt++) {
          try {
            final res = await http
                .post(
                  notifyUrl,
                  headers: {'Content-Type': 'application/json'},
                  body: payload,
                )
                .timeout(const Duration(seconds: 45));
            if (res.statusCode == 200) return true;
            debugPrint('⚠️ Server returned ${res.statusCode}: ${res.body}');
          } catch (e) {
            debugPrint('⚠️ Registration attempt ${attempt + 1} failed: $e');
          }
          if (attempt < 3) {
            await Future.delayed(Duration(seconds: 4 * (attempt + 1)));
            if (attempt == 1) await ensureBackendAwake();
          }
        }
        return false;
      }

      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final request = http.MultipartRequest('POST', notifyUrl);
          request.fields['name'] = name;
          request.fields['phone'] = phone;
          request.fields['reg_id'] = regId;
          request.fields['details'] = details;
          request.fields['type'] = type;

          for (final f in images) {
            request.files.add(
              http.MultipartFile.fromBytes(
                'photos',
                f['bytes'] as Uint8List,
                filename: f['name'] as String,
                contentType: _getContentType(f['name'] as String),
              ),
            );
          }
          for (final f in docs) {
            request.files.add(
              http.MultipartFile.fromBytes(
                'docs',
                f['bytes'] as Uint8List,
                filename: f['name'] as String,
                contentType: _getContentType(f['name'] as String),
              ),
            );
          }

          final streamed = await request.send().timeout(
            const Duration(seconds: 90),
          );
          final res = await http.Response.fromStream(streamed);
          if (res.statusCode == 200) return true;
          debugPrint('⚠️ Multipart attempt ${attempt + 1}: ${res.statusCode}');
        } catch (e) {
          debugPrint('⚠️ Multipart attempt ${attempt + 1} failed: $e');
        }
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 5 * (attempt + 1)));
          await ensureBackendAwake();
        }
      }
      return false;
    } catch (e) {
      debugPrint('❌ _notifyServerWithFiles failed: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  DIRECT TELEGRAM FALLBACK
  //  Used when server.py (port 3000) is unreachable.
  //
  //  KEY RULE: The first file ALWAYS carries the full info text as
  //  caption → photo + info appear TOGETHER in ONE message.
  //  Extra files follow as separate messages below.
  //  If there are NO files, the text is sent as a normal message.
  // ─────────────────────────────────────────────────────────────
  static Future<void> _sendTelegramDirectly({
    required String message,
    List<Map<String, dynamic>>? files,
    String? note,
  }) async {
    try {
      final fullText = note != null ? '$message\n$note' : message;
      final allFiles = (files ?? []).where((f) {
        final b = f['bytes'] as Uint8List?;
        return b != null && b.isNotEmpty;
      }).toList();

      // ── NO FILES: send text only ──
      if (allFiles.isEmpty) {
        await http
            .post(
              Uri.parse('https://api.telegram.org/bot$bot1Token/sendMessage'),
              body: {'chat_id': chatId, 'text': fullText},
            )
            .timeout(const Duration(seconds: 15));
        debugPrint('✅ Direct Telegram: text sent (no files)');
        return;
      }

      // ── FIRST FILE: send WITH full info text as caption ──────────────
      //    This guarantees photo+info are ALWAYS in one message.
      final first = allFiles[0];
      final firstBytes = first['bytes'] as Uint8List;
      final firstName = first['name'] as String? ?? 'file';
      final caption = fullText.length > 1024
          ? fullText.substring(0, 1024)
          : fullText;
      bool firstSent = false;

      try {
        final endpoint = _isImage(first) ? 'sendPhoto' : 'sendDocument';
        final field = _isImage(first) ? 'photo' : 'document';
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.telegram.org/bot$bot1Token/$endpoint'),
        );
        req.fields['chat_id'] = chatId;
        req.fields['caption'] = caption;
        req.files.add(
          http.MultipartFile.fromBytes(
            field,
            firstBytes,
            filename: firstName,
            contentType: _getContentType(firstName),
          ),
        );
        final stream = await req.send().timeout(const Duration(seconds: 30));
        await http.Response.fromStream(stream);
        firstSent = true;
        debugPrint('✅ Direct: first file + caption TOGETHER ($firstName)');
      } catch (e) {
        debugPrint('⚠️ Could not send first file $firstName: $e');
      }

      // If first file failed → send text-only as fallback
      if (!firstSent) {
        await http
            .post(
              Uri.parse('https://api.telegram.org/bot$bot1Token/sendMessage'),
              body: {'chat_id': chatId, 'text': fullText},
            )
            .timeout(const Duration(seconds: 15));
        debugPrint('✅ Direct: text-only fallback (first file upload failed)');
      }

      // ── REMAINING FILES: send without caption ─────────────────────────
      for (int i = 1; i < allFiles.length; i++) {
        final f = allFiles[i];
        final bytes = f['bytes'] as Uint8List;
        final fname = f['name'] as String? ?? 'file';
        try {
          final endpoint = _isImage(f) ? 'sendPhoto' : 'sendDocument';
          final field = _isImage(f) ? 'photo' : 'document';
          final req = http.MultipartRequest(
            'POST',
            Uri.parse('https://api.telegram.org/bot$bot1Token/$endpoint'),
          );
          req.fields['chat_id'] = chatId;
          req.files.add(
            http.MultipartFile.fromBytes(
              field,
              bytes,
              filename: fname,
              contentType: _getContentType(fname),
            ),
          );
          final s = await req.send().timeout(const Duration(seconds: 30));
          await http.Response.fromStream(s);
          debugPrint('✅ Direct: extra file sent ($fname)');
        } catch (fe) {
          debugPrint('⚠️ Could not send file $fname: $fe');
        }
      }
    } catch (e) {
      debugPrint('❌ Direct Telegram send error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────────────────────
  static bool _isImage(Map<String, dynamic> f) {
    final n = (f['name'] as String).toLowerCase();
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.heic') ||
        n.endsWith('.webp');
  }

  static MediaType _getContentType(String fileName) {
    final n = fileName.toLowerCase();
    if (n.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (n.endsWith('.jpg') || n.endsWith('.jpeg'))
      return MediaType('image', 'jpeg');
    if (n.endsWith('.png')) return MediaType('image', 'png');
    if (n.endsWith('.webp')) return MediaType('image', 'webp');
    if (n.endsWith('.heic')) return MediaType('image', 'heic');
    if (n.endsWith('.mp4')) return MediaType('video', 'mp4');
    if (n.endsWith('.mp3')) return MediaType('audio', 'mpeg');
    if (n.endsWith('.doc') || n.endsWith('.docx'))
      return MediaType('application', 'msword');
    return MediaType('application', 'octet-stream');
  }

  // ─────────────────────────────────────────────────────────────
  //  CONTENT / ADVERTS
  // ─────────────────────────────────────────────────────────────
  static Future<bool> deleteContent(int messageId) async {
    try {
      final deleteUrl = backendUrl.replaceAll('/content', '/content/delete');
      final res = await http
          .post(
            Uri.parse(deleteUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'message_id': messageId}),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        debugPrint('✅ Deleted content with message_id=$messageId');
        return true;
      }
      debugPrint('❌ Failed to delete: ${res.body}');
      return false;
    } catch (e) {
      debugPrint('❌ Delete error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchBotContent() async {
    List<Map<String, dynamic>> result = [];

    // ── TRY 1: Backend API (server.py) ──
    try {
      await ensureBackendAwake();
      final res = await http
          .get(Uri.parse(backendUrl))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        debugPrint('✅ Fetched ${data.length} items from Backend');
        result = data.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          if (map['date'] is String) {
            try {
              map['date'] = DateTime.parse(map['date'] as String);
            } catch (_) {
              map['date'] = DateTime.now();
            }
          }
          if (map['message_id'] != null) {
            map['message_id'] =
                int.tryParse(map['message_id'].toString()) ?? map['message_id'];
          }
          return map;
        }).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Backend not reachable: $e');
    }

    // ── TRY 2: Fallback to direct Telegram API ──
    if (result.isEmpty) {
      try {
        final url = Uri.parse(
          'https://api.telegram.org/bot$bot2Token/getUpdates?limit=50&offset=-50',
        );
        final response = await http
            .get(url)
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          if (data['ok'] != true) return [];

          final List updates = data['result'] as List? ?? [];
          final contentList = <Map<String, dynamic>>[];

          for (var update in updates) {
            final msg =
                update['message'] ??
                update['channel_post'] ??
                update['edited_message'] ??
                update['edited_channel_post'];
            if (msg == null) continue;

            String? type;
            String? fileId;
            String? text = (msg['text'] ?? msg['caption'] ?? '') as String?;

            if (msg['photo'] != null) {
              type = 'image';
              fileId = (msg['photo'] as List).last['file_id'] as String?;
            } else if (msg['video'] != null) {
              type = 'video';
              fileId = msg['video']['file_id'] as String?;
            } else if (msg['video_note'] != null) {
              type = 'video';
              fileId = msg['video_note']['file_id'] as String?;
            } else if (msg['document'] != null) {
              final doc = msg['document'] as Map<String, dynamic>;
              final mime = doc['mime_type']?.toString() ?? '';
              if (mime.startsWith('image/'))
                type = 'image';
              else if (mime.startsWith('video/'))
                type = 'video';
              else if (mime == 'application/pdf')
                type = 'pdf';
              else
                type = 'doc';
              fileId = doc['file_id'] as String?;
              if (text!.isEmpty)
                text = doc['file_name'] as String? ?? 'Document';
            } else if (msg['audio'] != null || msg['voice'] != null) {
              type = 'audio';
              fileId =
                  ((msg['audio'] ?? msg['voice'])
                          as Map<String, dynamic>)['file_id']
                      as String?;
            } else if (msg['text'] != null) {
              type = 'text';
            }

            if (type != null) {
              final int? msgId = msg['message_id'] is int
                  ? msg['message_id'] as int
                  : int.tryParse(msg['message_id']?.toString() ?? '');
              contentList.add({
                'type': type,
                'title': (text ?? '').isEmpty
                    ? (type == 'text' ? 'Announcement' : 'Attachment')
                    : text,
                'file_id': fileId,
                'message_id': msgId,
                'date': DateTime.fromMillisecondsSinceEpoch(
                  (msg['date'] as int) * 1000,
                ),
              });
            }
          }

          // Deduplicate
          final unique = <String, Map<String, dynamic>>{};
          for (var item in contentList) {
            unique['${item['type']}_${item['message_id']}'] = item;
          }
          result = unique.values.toList().reversed.toList();
        }
      } catch (e) {
        debugPrint('Error fetching Telegram fallback: $e');
      }
    }

    // ── RESOLVE DIRECT TELEGRAM DOWNLOAD URLs ──
    if (result.isNotEmpty) {
      await Future.wait(
        result.map((item) async {
          final fileId = item['file_id'] as String?;
          if (fileId != null && fileId.isNotEmpty) {
            final directUrl = await getDirectFileUrl(fileId);
            if (directUrl != null) item['direct_url'] = directUrl;
            item['proxy_url'] =
                '$_proxyUrl?file_id=${Uri.encodeComponent(fileId)}';
          }
        }),
      );
    }

    return result;
  }
}

/// Cached URL with expiry (Telegram file URLs last ~1 hour)
class _CachedUrl {
  final String url;
  final DateTime timestamp;

  _CachedUrl(this.url) : timestamp = DateTime.now();

  bool get isExpired => DateTime.now().difference(timestamp).inMinutes > 50;
}
