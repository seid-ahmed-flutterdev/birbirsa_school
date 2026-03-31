import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BirbirsaSchoolApp());
}

class BirbirsaSchoolApp extends StatelessWidget {
  const BirbirsaSchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Birbirsa Secondary School',
      theme: AppTheme.darkTheme,
      home: const HomePage(),
    );
  }
}
