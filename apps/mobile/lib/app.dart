import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/shared/widgets/app_shell.dart';

class CrimeReportApp extends StatelessWidget {
  const CrimeReportApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Set system UI overlay style for dark theme
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      title: 'CrImEreport',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppShell(),
    );
  }
}
