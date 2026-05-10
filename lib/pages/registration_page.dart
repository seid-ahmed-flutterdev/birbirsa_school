import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/app_colors.dart';
import '../services/telegram_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_background.dart';
import '../widgets/form_widgets.dart';
import '../widgets/camera_dialog.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _selectedGrade;
  String? _selectedSection;
  String? _selectedStream;

  List<Map<String, dynamic>> _registrationFiles = [];
  bool _isSubmitting = false;

  final List<String> _grades = ['9', '10', '11', '12'];
  final List<String> _sections = ['A', 'B', 'C', 'D'];
  final List<String> _streams = ['Natural Science', 'Social Science'];

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true, // Required to get file bytes on mobile devices
    );
    if (result != null) {
      setState(() {
        for (var file in result.files) {
          if (file.bytes != null) {
            _registrationFiles.add({'name': file.name, 'bytes': file.bytes});
          }
        }
      });
    }
  }

  Future<void> _captureCamera() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const WebCameraCapture(),
    );

    if (result != null) {
      setState(() {
        _registrationFiles.add({
          'name': 'Capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
          'bytes': result['bytes'],
        });
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final success = await TelegramService.sendRegistration(
      fullName: _nameController.text,
      fatherName: _fatherNameController.text,
      motherName: _motherNameController.text,
      phoneNumber: _phoneController.text,
      grade: _selectedGrade!,
      section: _selectedSection!,
      stream: _selectedStream,
      files: _registrationFiles,
    );

    setState(() => _isSubmitting = false);

    if (success) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.accent,
          title: const Text('Success!', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Your registration request has been submitted successfully.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(color: AppColors.highlight),
              ),
            ),
          ],
        ),
      );
    }
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
                      title: 'Student Registration',
                      subtitle: 'Step 1: Fill in your details',
                    ),
                    const SizedBox(height: 40),
                    GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionTitle(title: 'Personal Info'),
                              const SizedBox(height: 20),
                              CustomTextField(
                                controller: _nameController,
                                label: 'Full Name',
                                icon: Icons.person,
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _fatherNameController,
                                label: 'Father\'s Name',
                                icon: Icons.man,
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _motherNameController,
                                label: 'Mother\'s Name',
                                icon: Icons.woman,
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
                              const SectionTitle(title: 'Academic Selection'),
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
                              const SectionTitle(title: 'Documents & Files'),
                              const SizedBox(height: 20),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  ActionButton(
                                    icon: Icons.upload_file,
                                    label: 'Upload Files',
                                    onTap: _pickFile,
                                  ),
                                  ActionButton(
                                    icon: Icons.camera_alt,
                                    label: 'Capture Photo',
                                    onTap: _captureCamera,
                                  ),
                                ],
                              ),
                              if (_registrationFiles.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _registrationFiles.length,
                                  itemBuilder: (ctx, i) => FileItem(
                                    name: _registrationFiles[i]['name'],
                                    onDelete: () => setState(
                                      () => _registrationFiles.removeAt(i),
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
                      label: 'Register Student',
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
