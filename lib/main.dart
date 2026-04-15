import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/main/main_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const AmanApp());
}

class AmanApp extends StatelessWidget {
  const AmanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'أمان',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              );
            },
            home: auth.isAuthenticated
                ? const MainShell()
                : const PhoneEntryScreen(),
          );
        },
      ),
    );
  }
}
