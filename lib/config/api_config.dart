import 'package:flutter/foundation.dart';

class ApiConfig {
  // ─────────────────────────────────────────────────────────────
  //  ✅ SET YOUR RENDER BACKEND URL HERE (once deployed)
  //  Example: 'https://birbirsa-backend.onrender.com'
  // ─────────────────────────────────────────────────────────────
  static const String _renderUrl = 'https://birbirsa-secondary-school.onrender.com';

  static String get baseUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      // Local development
      if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
        return 'http://localhost:3000';
      }
      // On Vercel/production — always use Render backend
      return _renderUrl;
    }
    // Native app — always use Render backend
    return _renderUrl;
  }

  static String get contentUrl        => '$baseUrl/api/content';
  static String get registrationsUrl  => '$baseUrl/api/registrations';
  static String get notifyUrl         => '$baseUrl/api/notify-registration';
  static String get proxyUrl          => '$baseUrl/api/proxy';
  static String get deleteUrl         => '$baseUrl/api/content/delete';
  static String get healthUrl         => '$baseUrl/health';
}
