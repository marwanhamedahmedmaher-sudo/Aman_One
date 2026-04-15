# Aman Sales App (أمان) — Architecture Reference

Arabic RTL merchant registration and sales platform built with Flutter.

## Tech Stack

- **Framework:** Flutter (SDK ^3.11.4)
- **Language:** Dart
- **State Management:** Provider (`ChangeNotifierProvider`)
- **UI:** Material 3 with custom theme (`AppTheme.lightTheme`)
- **Fonts:** Google Fonts
- **Image Handling:** image_picker

## Architecture

```
lib/
├── main.dart                  # App entry point, routing, localization
├── theme/app_theme.dart       # Material theme configuration
├── models/                    # Data models (User, Merchant)
├── providers/                 # State management (AuthProvider, MerchantProvider)
├── widgets/                   # Reusable widgets (OtpInput, AuthHeader, StepIndicator)
└── screens/
    ├── auth/                  # Phone entry, OTP, password, forgot password
    ├── main/                  # MainShell, HomeScreen, TasksScreen, ProfileScreen
    └── merchant/              # Multi-step merchant registration flow
```

## Commands

```bash
flutter pub get          # Install dependencies
flutter run -d chrome    # Run on Chrome (web)
flutter analyze          # Static analysis
flutter test             # Run tests
```

## Conventions

- **Language:** Arabic-only, RTL layout enforced via `Directionality` wrapper
- **Locale:** `Locale('ar')` with Material/Cupertino/Widgets localization delegates
- **Assets:** Images in `assets/images/` (declared in pubspec.yaml)
- **State:** Use Provider pattern — create models in `models/`, state in `providers/`
- **Screens:** Organize by feature under `lib/screens/`
