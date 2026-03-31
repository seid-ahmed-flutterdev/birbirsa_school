import 'package:flutter/material.dart';
import '../core/app_colors.dart';

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

class HeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const HeroHeader({super.key, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: 48,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppColors.highlight,
          letterSpacing: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle({super.key, required this.title});
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  );
}

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
  });
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white),
    validator: (v) => v!.isEmpty ? 'Field required' : null,
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: AppColors.highlight, size: 20),
      labelText: label,
    ),
  );
}

class CustomDropdown extends StatelessWidget {
  final String? value;
  final String label;
  final List<String> items;
  final Function(String?) onChanged;
  const CustomDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value,
    style: const TextStyle(color: Colors.white),
    items: items
        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
        .toList(),
    onChanged: onChanged,
    validator: (v) => v == null ? 'Selection required' : null,
    decoration: InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    ),
    dropdownColor: AppColors.primary,
  );
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

class FileItem extends StatelessWidget {
  final String name;
  final VoidCallback onDelete;
  final Color? color;
  const FileItem({
    super.key,
    required this.name,
    required this.onDelete,
    this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white12,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(Icons.description, color: color ?? Colors.white70, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 14, color: Colors.white),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: Colors.greenAccent),
          onPressed: onDelete,
        ),
      ],
    ),
  );
}

class SubmitButton extends StatelessWidget {
  final bool isSubmitting;
  final VoidCallback onTap;
  final String label;
  const SubmitButton({
    super.key,
    required this.isSubmitting,
    required this.onTap,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: isSubmitting ? null : onTap,
    child: Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.highlight, Color(0xFF69F0AE)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.highlight.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: isSubmitting
            ? const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    ),
  );
}
