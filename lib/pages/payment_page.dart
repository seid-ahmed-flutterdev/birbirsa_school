import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/app_colors.dart';
import '../services/telegram_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_background.dart';
import '../widgets/form_widgets.dart';
import '../widgets/camera_dialog.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _selectedGrade;
  String? _selectedSection;
  String? _selectedStream;

  // Changed from single file to a list to support multiple uploads
  List<Map<String, dynamic>> _receiptFiles = [];
  bool _isSubmitting = false;

  final List<String> _grades = ['9', '10', '11', '12'];
  final List<String> _sections = ['A', 'B', 'C', 'D'];
  final List<String> _streams = ['Natural Science', 'Social Science'];

  Future<void> _pickReceipt() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true, // Required to get file bytes reliably on all platforms
    );
    if (result != null) {
      setState(() {
        for (var file in result.files) {
          if (file.bytes != null) {
            _receiptFiles.add({'name': file.name, 'bytes': file.bytes});
          }
        }
      });
    }
  }

  Future<void> _captureReceipt() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const WebCameraCapture(),
    );

    if (result != null) {
      setState(() {
        _receiptFiles.add({
          'name':
              'Receipt_Capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
          'bytes': result['bytes'],
        });
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_receiptFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload or capture at least one receipt.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final serverSaved = await TelegramService.sendPayment(
      fullName: _nameController.text,
      phoneNumber: _phoneController.text,
      grade: _selectedGrade!,
      section: _selectedSection!,
      stream: _selectedStream,
      receipts: _receiptFiles,
    );

    setState(() => _isSubmitting = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.accent,
        title: Text(
          serverSaved ? 'Success!' : 'Sent to director',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          serverSaved
              ? 'Your payment receipt was saved. The director was notified on Telegram.'
              : 'The director received your receipt on Telegram, but the school server was waking up. '
                  'Please wait one minute and submit again if the School Bot cannot find your payment.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
              style: TextStyle(color: AppColors.highlight),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: Stack(
          children: [
            SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 20),
          child: Center(
            child: MaxWidthContainer(
              maxWidth: 800,
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const HeroHeader(
                      title: 'Fee Payment',
                      subtitle: 'Step 2: Submit your payment proof',
                    ),
                    const SizedBox(height: 40),
                    GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionTitle(
                                title: 'Guardian/Student Info',
                              ),
                              const SizedBox(height: 20),
                              CustomTextField(
                                controller: _nameController,
                                label: 'Full Name',
                                icon: Icons.person,
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _phoneController,
                                label: 'Phone Number',
                                icon: Icons.phone,
                                keyboardType: TextInputType.phone,
                              ),
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 600.ms)
                        .moveY(begin: 30, end: 0),
                    const SizedBox(height: 30),
                    GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionTitle(title: 'Class Details'),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: CustomDropdown(
                                      value: _selectedGrade,
                                      label: 'Grade',
                                      items: _grades,
                                      onChanged: (val) => setState(() {
                                        _selectedGrade = val;
                                        if (val != '11' && val != '12')
                                          _selectedStream = null;
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: CustomDropdown(
                                      value: _selectedSection,
                                      label: 'Section',
                                      items: _sections,
                                      onChanged: (val) => setState(
                                        () => _selectedSection = val,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_selectedGrade == '11' ||
                                  _selectedGrade == '12') ...[
                                const SizedBox(height: 16),
                                CustomDropdown(
                                  value: _selectedStream,
                                  label: 'Science Stream',
                                  items: _streams,
                                  onChanged: (val) =>
                                      setState(() => _selectedStream = val),
                                ),
                              ],
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 200.ms)
                        .moveX(begin: 30, end: 0),
                    const SizedBox(height: 30),
                    GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionTitle(title: 'Receipt Submission'),
                              const SizedBox(height: 8),
                              const Text(
                                'You can upload multiple receipt images or documents.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  ActionButton(
                                    icon: Icons.receipt_long,
                                    label: 'Upload Receipts',
                                    onTap: _pickReceipt,
                                    color: AppColors.highlight,
                                  ),
                                  ActionButton(
                                    icon: Icons.camera,
                                    label: 'Capture Receipt',
                                    onTap: _captureReceipt,
                                    color: AppColors.highlight,
                                  ),
                                ],
                              ),
                              if (_receiptFiles.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _receiptFiles.length,
                                  itemBuilder: (ctx, i) => FileItem(
                                    name: _receiptFiles[i]['name'],
                                    color: AppColors.highlight,
                                    onDelete: () => setState(
                                      () => _receiptFiles.removeAt(i),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 400.ms)
                        .moveY(begin: 30, end: 0),
                    const SizedBox(height: 50),
                    SubmitButton(
                      isSubmitting: _isSubmitting,
                      onTap: _submit,
                      label: 'Submit Payment',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
            // ── Back Arrow Button ──
            Positioned(
              top: 40,
              left: 16,
              child: SafeArea(
                child: Material(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
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
