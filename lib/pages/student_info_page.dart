import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_background.dart';
import 'home_page.dart'; // for SectionTitle, HeroHeader, MaxWidthContainer, ActionButton
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

class StudentInfoPage extends StatefulWidget {
  const StudentInfoPage({super.key});

  @override
  State<StudentInfoPage> createState() => _StudentInfoPageState();
}

class _StudentInfoPageState extends State<StudentInfoPage> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isSending = false;
  List<Map<String, dynamic>> _results = [];
  String? _errorMsg;
  String? _statusMsg;

  String get _origin => ApiConfig.baseUrl;

  Future<void> _search() async {

    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _results = [];
      _errorMsg = null;
      _statusMsg = null;
    });

    try {
      final url = Uri.parse(
        '$_origin/api/registrations/search?q=${Uri.encodeComponent(query)}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list =
            (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _results = list;
          if (list.isEmpty) _errorMsg = 'No student found for "$query"';
        });
      } else {
        setState(
          () => _errorMsg =
              'Server error (${res.statusCode}). Is the server running?',
        );
      }
    } catch (e) {
      setState(() => _errorMsg = 'Cannot reach server: $e');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  /// Resend a saved record to the bot so the director can review it again
  Future<void> _sendToBot(Map<String, dynamic> record) async {
    setState(() {
      _isSending = true;
      _statusMsg = null;
    });
    try {
      final url = Uri.parse('$_origin/api/notify-registration');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'name': record['name'] ?? '',
              'phone': record['phone'] ?? '',
              'reg_id': _extractId(record['details'] ?? ''),
              'details': record['details'] ?? '',
              'type': record['type'] ?? 'registration',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        setState(() => _statusMsg = '✅ Sent to bot! Check your Telegram.');
      } else {
        setState(() => _statusMsg = '⚠️ Server returned ${res.statusCode}');
      }
    } catch (e) {
      setState(() => _statusMsg = '❌ Failed: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  String _extractId(String details) {
    final m = RegExp(
      r'ID:\s*([A-Z]+\d+)',
      caseSensitive: false,
    ).firstMatch(details);
    return m?.group(1) ?? '';
  }

  String _extractField(String details, String label) {
    final m = RegExp(
      '$label\\s*:\\s*(.+)',
      caseSensitive: false,
    ).firstMatch(details);
    return m?.group(1)?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
          child: Center(
            child: MaxWidthContainer(
              maxWidth: 900,
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios,
                          color: Colors.white70,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: HeroHeader(
                          title: 'Student Info',
                          subtitle: 'SEARCH & MANAGE RECORDS',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // ── Search Card ──
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(title: '🔍 Search Student'),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Enter name, phone or ID...',
                                  hintStyle: const TextStyle(
                                    color: Colors.white38,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: AppColors.highlight,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white10,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: AppColors.highlight,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => _search(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              child: ElevatedButton.icon(
                                onPressed: _isSearching ? null : _search,
                                icon: _isSearching
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.search),
                                label: const Text('Search'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.highlight,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_errorMsg != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMsg!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_statusMsg != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.greenAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _statusMsg!,
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(duration: 600.ms).moveY(begin: 20, end: 0),

                  const SizedBox(height: 24),

                  // ── Results ──
                  if (_results.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_results.length} result(s) found',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(_results.length, (i) {
                      final r = _results[i];
                      final det = r['details'] as String? ?? '';
                      final name = r['name'] ?? _extractField(det, 'Student');
                      final phone = r['phone'] ?? _extractField(det, 'Phone');
                      final grade = _extractField(det, 'Grade');
                      final section = _extractField(det, 'Section');
                      final stream = _extractField(det, 'Stream');
                      final father = _extractField(det, 'Father');
                      final mother = _extractField(det, 'Mother');
                      final rid = _extractId(det);
                      final date = (r['date'] as String? ?? '').length >= 10
                          ? (r['date'] as String).substring(0, 10)
                          : r['date'] ?? '';
                      final rtype = r['type'] ?? 'registration';
                      final badge = rtype == 'registration'
                          ? '📝 REGISTRATION'
                          : '💸 PAYMENT';
                      final badgeColor = rtype == 'registration'
                          ? AppColors.highlight
                          : Colors.deepPurpleAccent;

                      return GlassCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: badgeColor.withOpacity(0.4),
                                        ),
                                      ),
                                      child: Text(
                                        badge,
                                        style: TextStyle(
                                          color: badgeColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      date,
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _infoRow(Icons.person, 'Name', name),
                                if (phone.isNotEmpty)
                                  _infoRow(Icons.phone, 'Phone', phone),
                                if (grade.isNotEmpty)
                                  _infoRow(Icons.school, 'Grade', grade),
                                if (section.isNotEmpty)
                                  _infoRow(Icons.class_, 'Section', section),
                                if (stream.isNotEmpty)
                                  _infoRow(Icons.science, 'Stream', stream),
                                if (father.isNotEmpty)
                                  _infoRow(Icons.man, 'Father', father),
                                if (mother.isNotEmpty)
                                  _infoRow(Icons.woman, 'Mother', mother),
                                if (rid.isNotEmpty)
                                  _infoRow(Icons.badge, 'ID', rid),
                                const SizedBox(height: 16),
                                // ── SEND TO BOT BUTTON ──
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isSending
                                        ? null
                                        : () => _sendToBot(r),
                                    icon: _isSending
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.send, size: 18),
                                    label: const Text('📲 Send to Bot'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepPurpleAccent
                                          .withOpacity(0.7),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .animate()
                          .fadeIn(delay: (i * 150).ms, duration: 500.ms)
                          .moveY(begin: 20, end: 0);
                    }),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.highlight),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
