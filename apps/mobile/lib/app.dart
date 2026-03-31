import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/splash/presentation/splash_screen.dart';
import 'package:crimereport/shared/providers/notification_providers.dart';
import 'package:crimereport/shared/services/deep_link_handler.dart';

class CrimeReportApp extends ConsumerWidget {
  const CrimeReportApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(initNotificationsProvider);
    ref.watch(deepLinkProvider);

    final navigatorKey = ref.watch(navigatorKeyProvider);

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
      navigatorKey: navigatorKey,
      home: const SplashScreen(),
    );
  }
}
