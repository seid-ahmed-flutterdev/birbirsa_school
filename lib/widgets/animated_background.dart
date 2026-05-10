import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/app_colors.dart';

class AnimatedBackground extends StatelessWidget {
  final Widget child;

  const AnimatedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base Gradient
        Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),

        // Blurred Floating Blobs
        Positioned(
          top: -100,
          left: -100,
          child:
              Container(
                    width: 400,
                    height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.highlight.withOpacity(0.15),
                    ),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .move(
                    begin: const Offset(0, 0),
                    end: const Offset(50, 50),
                    duration: 8.seconds,
                    curve: Curves.easeInOut,
                  )
                  .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.2, 1.2),
                    duration: 10.seconds,
                  ),
        ),

        Positioned(
          bottom: -50,
          right: -50,
          child:
              Container(
                    width: 300,
                    height: 300,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent,
                    ),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .move(
                    begin: const Offset(0, 0),
                    end: const Offset(-40, -40),
                    duration: 6.seconds,
                    curve: Curves.easeInOut,
                  )
                  .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(0.9, 0.9),
                    duration: 7.seconds,
                  ),
        ),

        // Hero Parallax Background (The school image)
        // For development, we use a placeholder or image from assets if available.
        Opacity(
          opacity: 0.15,
          child: Image.network(
            'https://images.unsplash.com/photo-1546410531-bb4caa6b424d?auto=format&fit=crop&q=80&w=2070',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),

        // Page Content
        child,
      ],
    );
  }
}
