import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_background.dart';
import '../config/api_config.dart';
import '../services/telegram_service.dart';
import 'registration_page.dart';
import 'payment_page.dart';
import 'student_info_page.dart';
import 'content_preview_page.dart';
import 'dart:async';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _content = [];
  bool _isLoadingContent = true;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadContent();
    // Auto-refresh every 10 seconds — no manual refresh needed
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadContentSilently();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() => _isLoadingContent = true);
    final content = await TelegramService.fetchBotContent();
    setState(() {
      _content = content;
      _isLoadingContent = false;
    });
  }

  // Silent refresh — no loading indicator, just update data
  // NOTE: We always update (even if empty) so deletions are reflected immediately
  Future<void> _loadContentSilently() async {
    final content = await TelegramService.fetchBotContent();
    if (mounted) {
      setState(() {
        _content = content;
      });
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final messageId = item['message_id'];
    if (messageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete: no message ID'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Content?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${item['title']?.toString().substring(0, (item['title']?.toString().length ?? 0) > 50 ? 50 : item['title']?.toString().length ?? 0) ?? 'this item'}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await TelegramService.deleteContent(messageId);
      if (success && mounted) {
        setState(() {
          _content.removeWhere((c) => c['message_id'] == messageId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Content deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to delete. Is the server running?'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeroSection(context),
              _buildAboutSection(context),
              _buildCampusFeatureSection(context),
              _buildAdvertSection(context),
              _buildRulesSection(context),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const HeroHeader(
                  title: 'BIRBIRSA SCHOOL',
                  subtitle: 'EXCELLENCE IN EDUCATION & INNOVATION',
                )
                .animate()
                .fadeIn(duration: 800.ms)
                .scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 48),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _buildMainButton(
                  'Student Registration',
                  Icons.how_to_reg,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegistrationPage()),
                  ),
                ),
                _buildMainButton(
                  'Fee Payment',
                  Icons.receipt_long,
                  color: AppColors.highlight,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaymentPage()),
                  ),
                ),
                _buildMainButton(
                  'Student Info',
                  Icons.manage_search,
                  color: Colors.deepPurpleAccent,
                  onTap: () => _showPasswordDialog(),
                ),
              ],
            ).animate().fadeIn(delay: 500.ms).moveY(begin: 30, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildMainButton(
    String label,
    IconData icon, {
    VoidCallback? onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        color: (color ?? AppColors.highlight).withOpacity(0.2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      color: Colors.black12,
      child: MaxWidthContainer(
        maxWidth: 1200,
        child: Column(
          children: [
            const SectionTitle(title: 'About Our School'),
            const SizedBox(height: 16),
            const Text(
              'Birbirsa Secondary School provides a modern learning environment tailored for excellence. '
              'Enjoy entirely free learning—no fees required, just register and start your journey.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 48),
            Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                _buildFeatureCard(
                  Icons.science,
                  'Laboratory',
                  'Fully equipped modern science lab.',
                ),
                _buildFeatureCard(
                  Icons.school,
                  'Modern Classes',
                  'Comfortable and advanced classrooms.',
                ),
                _buildFeatureCard(
                  Icons.computer,
                  'Modern ICT Class',
                  'State-of-the-art computer labs.',
                ),
                _buildFeatureCard(
                  Icons.sports_soccer,
                  'Football Area',
                  'Standard football pitch for sports.',
                ),
                _buildFeatureCard(
                  Icons.park,
                  'Green Area',
                  'Beautiful green campus environment.',
                ),
                _buildFeatureCard(
                  Icons.menu_book,
                  'Reader Place',
                  'Quiet reading areas surrounded by nature.',
                ),
                _buildFeatureCard(
                  Icons.money_off,
                  'Free Learning',
                  'No tuition fees! Just register to learn.',
                ),
                _buildFeatureCard(
                  Icons.lightbulb,
                  'Modern Learning',
                  'Innovative teaching methodologies.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String subtitle) {
    return GlassCard(
      width: 260,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.highlight.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.highlight, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildCampusFeatureSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: MaxWidthContainer(
        maxWidth: 1200,
        child: Column(
          children: [
            const SectionTitle(title: 'Campus Tour'),
            const SizedBox(height: 16),
            const Text(
              'Explore our beautiful campus and state-of-the-art facilities designed for modern learning.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 48),
            Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                _buildCampusImageCard(
                  'assets/images/campus1.jpg',
                  'Main Entrance',
                ),
                _buildCampusImageCard(
                  'assets/images/campus2.jpg',
                  'Green Environment & Walkways',
                ),
                _buildCampusImageCard(
                  'assets/images/campus3.jpg',
                  'Modern Classrooms & Facilities',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampusImageCard(String imagePath, String title) {
    return GlassCard(
      width: 350,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Image.asset(imagePath, height: 250, fit: BoxFit.cover),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildAdvertSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: MaxWidthContainer(
        maxWidth: 1200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionTitle(title: 'What\'s New (Adverts)'),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Live',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Stay updated with the latest events and announcements from our school bot.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 40),
            if (_isLoadingContent)
              const Center(child: CircularProgressIndicator())
            else if (_content.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'No announcements found. Post something to your bot!',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
              )
            else
              _buildContentGrid(
                _content
                    .where((e) => e['type'] != 'pdf' && e['type'] != 'doc')
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      color: Colors.black12,
      child: MaxWidthContainer(
        maxWidth: 1000,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: 'School Rules & Documents'),
            const SizedBox(height: 40),
            if (_isLoadingContent)
              const Center(child: CircularProgressIndicator())
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _content
                    .where((e) => e['type'] == 'pdf' || e['type'] == 'doc')
                    .length,
                itemBuilder: (ctx, i) {
                  final item = _content
                      .where((e) => e['type'] == 'pdf' || e['type'] == 'doc')
                      .toList()[i];
                  return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: GlassCard(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Icon(
                                item['type'] == 'pdf'
                                    ? Icons.picture_as_pdf
                                    : Icons.description,
                                color: item['type'] == 'pdf'
                                    ? Colors.greenAccent
                                    : Colors.blueAccent,
                                size: 40,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['title'],
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      item['type'] == 'pdf'
                                          ? 'PDF Document'
                                          : 'Downloadable File',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ActionButton(
                                icon: Icons.visibility,
                                label: 'View',
                                onTap: () => _openMediaUrl(item),
                                color: AppColors.highlight,
                              ),
                              const SizedBox(width: 8),
                              ActionButton(
                                icon: Icons.delete,
                                label: 'Delete',
                                onTap: () => _deleteItem(item),
                                color: Colors.greenAccent,
                              ),
                            ],
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(delay: (i * 100).ms)
                      .moveX(begin: -20, end: 0);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentGrid(List<Map<String, dynamic>> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
        childAspectRatio: 0.8,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        IconData typeIcon;
        Color typeColor;

        switch (item['type']) {
          case 'video':
            typeIcon = Icons.video_library;
            typeColor = Colors.orangeAccent;
            break;
          case 'audio':
            typeIcon = Icons.audio_file;
            typeColor = Colors.purpleAccent;
            break;
          case 'pdf':
          case 'doc':
            typeIcon = Icons.description;
            typeColor = Colors.blueAccent;
            break;
          default:
            typeIcon = Icons.campaign;
            typeColor = AppColors.highlight;
        }

        return InkWell(
              onTap: () => _openMediaUrl(item),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                            child: Container(
                              width: double.infinity,
                              color: Colors.white10,
                              child:
                                  item['type'] == 'image' &&
                                      _getImageUrl(item) != null
                                  ? Image.network(
                                      _getImageUrl(item)!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      loadingBuilder: (context, child, progress) {
                                        if (progress == null) return child;
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                progress.expectedTotalBytes !=
                                                    null
                                                ? progress.cumulativeBytesLoaded /
                                                      progress
                                                          .expectedTotalBytes!
                                                : null,
                                            color: AppColors.highlight,
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stack) {
                                        return Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.image,
                                                size: 48,
                                                color: typeColor.withOpacity(
                                                  0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'Image',
                                                style: TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    )
                                  : Center(
                                      child: Icon(
                                        typeIcon,
                                        size: 64,
                                        color: typeColor.withOpacity(0.7),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title'] ?? 'No Title',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: typeColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item['type'].toString().toUpperCase(),
                                      style: TextStyle(
                                        color: typeColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatDate(item['date']),
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Delete button in top-right corner
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _deleteItem(item),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.greenAccent,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .animate()
            .fadeIn(delay: (i * 200).ms)
            .scale(begin: const Offset(0.9, 0.9));
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xFF0A0A1A)],
        ),
      ),
      child: Column(
        children: [
          // School footer row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              children: [
                const Divider(color: Colors.white12),
                const SizedBox(height: 24),
                const Text(
                  '© 2026 Birbirsa Secondary School. All Rights Reserved.',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Providing free, quality education for a brighter future.',
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Developer Credit Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.highlight.withOpacity(0.08),
                  Colors.purpleAccent.withOpacity(0.05),
                ],
              ),
              border: const Border(
                top: BorderSide(color: Colors.white10, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Flutter badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF54C5F8).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF54C5F8).withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flutter_dash,
                            color: Color(0xFF54C5F8),
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Built with Flutter',
                            style: TextStyle(
                              color: Color(0xFF54C5F8),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Developer name
                const Text(
                  'Developed by',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 4),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [AppColors.highlight, Colors.purpleAccent],
                  ).createShader(bounds),
                  child: const Text(
                    'Seid Ahmed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Social / link buttons
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildDevLink(
                      icon: Icons.language,
                      label: 'Portfolio',
                      color: AppColors.highlight,
                      url: 'https://seid-flutter-6b125.web.app',
                    ),
                    _buildDevLink(
                      icon: Icons.telegram,
                      label: 'Telegram',
                      color: const Color(0xFF29B6F6),
                      url: 'https://t.me/flutterwebsite',
                    ),
                    _buildDevLink(
                      icon: Icons.work_rounded,
                      label: 'LinkedIn',
                      color: const Color(0xFF0A66C2),
                      url:
                          'https://www.linkedin.com/in/web-app-2432043ab?utm_source=share&utm_campaign=share_via&utm_content=profile&utm_medium=android_app',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ).animate().fadeIn(duration: 800.ms),
        ],
      ),
    );
  }

  Widget _buildDevLink({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  PERMANENT FIX: Open media using DIRECT Telegram URL
  //  Works from ANY device, ANY browser, ANY network.
  //  No localhost/proxy dependency.
  // ─────────────────────────────────────────────────────────────
  void _openMediaUrl(Map<String, dynamic> item) {
    final type = item['type'] as String?;

    // Text items → show in a dialog (no URL needed)
    if (type == 'text') {
      _showTextPreviewDialog(item);
      return;
    }

    // Priority: proxy_url (CORS safe) > direct_url > url
    final url =
        (item['proxy_url'] as String?) ??
        (item['direct_url'] as String? ?? item['url'] as String? ?? '');

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file URL available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // On web, open PDFs/docs directly in a new browser tab
    // (LaunchMode.externalApplication does NOT work on Flutter Web)
    if (kIsWeb && (type == 'pdf' || type == 'doc')) {
      final resolvedUrl = url.startsWith('http://') || url.startsWith('https://')
          ? url
          : '${Uri.base.origin}$url';
      launchUrl(Uri.parse(resolvedUrl), mode: LaunchMode.platformDefault);
      return;
    }

    // Inject the resolved best URL so ContentPreviewPage can use it directly
    final updatedItem = Map<String, dynamic>.from(item);
    updatedItem['url'] = url;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ContentPreviewPage(item: updatedItem)),
    );
  }

  void _showTextPreviewDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.campaign, color: AppColors.highlight),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Announcement',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: _buildRichTextWithPhones(
            ctx,
            item['title']?.toString() ?? '',
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  PASSWORD DIALOG — protects Student Info page
  // ─────────────────────────────────────────────────────────────
  void _showPasswordDialog() {
    final passwordController = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: Colors.deepPurpleAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Access Required',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the password to access student records.',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: passwordController,
                    obscureText: obscure,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(
                        Icons.vpn_key,
                        color: Colors.deepPurpleAccent,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white38,
                        ),
                        onPressed: () {
                          setDialogState(() => obscure = !obscure);
                        },
                      ),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Colors.deepPurpleAccent,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onSubmitted: (_) {
                      _validatePassword(ctx, passwordController.text);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    _validatePassword(ctx, passwordController.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Unlock'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _validatePassword(BuildContext dialogContext, String password) {
    if (password == 'student123') {
      Navigator.pop(dialogContext);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StudentInfoPage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Incorrect password'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  PHONE NUMBER DETECTION — makes phone numbers clickable
  //  in advert bot content with call/copy options
  // ─────────────────────────────────────────────────────────────
  static final RegExp _phoneRegex = RegExp(
    r'(?:\+?\d[\d\s\-]{6,14}\d)',
  );

  Widget _buildRichTextWithPhones(BuildContext ctx, String text) {
    final matches = _phoneRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
          height: 1.6,
        ),
      );
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      // Add text before this phone number
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            height: 1.6,
          ),
        ));
      }

      // Add the clickable phone number
      final phoneNumber = match.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: InkWell(
          onTap: () => _showPhoneOptionsDialog(ctx, phoneNumber),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.greenAccent.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone, size: 14, color: Colors.greenAccent),
                const SizedBox(width: 4),
                Text(
                  phoneNumber,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.greenAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ));

      lastEnd = match.end;
    }

    // Add remaining text after last match
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
          height: 1.6,
        ),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  void _showPhoneOptionsDialog(BuildContext ctx, String phoneNumber) {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[\s\-]'), '');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.phone, color: Colors.greenAccent, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      phoneNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Call option
              _buildPhoneOption(
                icon: Icons.call,
                label: 'Call',
                subtitle: 'Make a phone call',
                color: Colors.greenAccent,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  launchUrl(Uri.parse('tel:$cleanNumber'));
                },
              ),
              // SMS option
              _buildPhoneOption(
                icon: Icons.message,
                label: 'Send SMS',
                subtitle: 'Open messaging app',
                color: Colors.blueAccent,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  launchUrl(Uri.parse('sms:$cleanNumber'));
                },
              ),
              // Copy option
              _buildPhoneOption(
                icon: Icons.copy,
                label: 'Copy Number',
                subtitle: 'Copy to clipboard',
                color: Colors.orangeAccent,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Clipboard.setData(ClipboardData(text: cleanNumber));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('📋 Copied: $cleanNumber'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhoneOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    );
  }

  /// Get the best image URL for thumbnails in the grid.
  /// Tries proxy_url first (CORS-safe for Image.network on web),
  /// then direct_url, then plain url.
  String? _getImageUrl(Map<String, dynamic> item) {
    final proxy = item['proxy_url'] as String?;
    final direct = item['direct_url'] as String?;
    final url = item['url'] as String?;

    if (proxy != null && proxy.isNotEmpty) return _resolveUrl(proxy);
    if (direct != null && direct.isNotEmpty) return direct;
    if (url != null && url.isNotEmpty) return _resolveUrl(url);
    return null;
  }

  /// Make any relative URL absolute.
  String _resolveUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (kIsWeb) {
      return '${Uri.base.origin}$url';
    }
    return '${ApiConfig.baseUrl}$url';
  }


  String _formatDate(dynamic date) {
    if (date is DateTime) {
      return "${date.day}/${date.month}/${date.year}";
    }
    if (date is String) {
      try {
        final parsed = DateTime.parse(date);
        return "${parsed.day}/${parsed.month}/${parsed.year}";
      } catch (_) {
        return date.length > 10 ? date.substring(0, 10) : date;
      }
    }
    return '';
  }
}

class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: (color ?? Colors.white).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (color ?? Colors.white).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle({super.key, required this.title});
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  );
}

class HeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const HeroHeader({super.key, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 64,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 2,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 18,
          color: AppColors.highlight,
          letterSpacing: 4,
        ),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class MaxWidthContainer extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  const MaxWidthContainer({
    super.key,
    required this.maxWidth,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: child,
  );
}
