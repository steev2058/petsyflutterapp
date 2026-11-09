import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Petsy visual system — sunlit coral on soft stone, with a calm teal accent.
class PetsyColors {
  static const primary = Color(0xFFFF5C2E);
  static const primaryDark = Color(0xFFD44318);
  static const primarySoft = Color(0xFFFFEDE6);
  static const secondary = Color(0xFFFF8F63);
  static const accent = Color(0xFF2F9E8F);
  static const accentSoft = Color(0xFFE6F5F2);

  static const background = Color(0xFFFFFBFA);
  static const backgroundAlt = Color(0xFFF7F1ED);
  static const surface = Color(0xFFFFFFFF);
  static const mist = Color(0xFFFFF3EC);
  static const shellWash = Color(0xFFF3EBE6);

  static const text = Color(0xFF241F1C);
  static const textSecondary = Color(0xFF7A726C);
  static const textLight = Color(0xFFA39A93);
  static const error = Color(0xFFE04545);
  static const success = Color(0xFF2F9E62);
  static const warning = Color(0xFFE39B2B);
  static const border = Color(0xFFE8DFD8);

  static const rating = Color(0xFFE39B2B);
  static const ratingSoft = Color(0xFFFFF4DF);
  static const ratingInk = Color(0xFF8A5A10);
  static const genderFemale = Color(0xFFD45B8C);
  static const genderMale = Color(0xFF3B82B0);
  static const ink = Color(0xFF1C1917);

  static const authTop = Color(0xFFFFFCFA);
  static const authMid = Color(0xFFFFF1E8);
  static const authBottom = Color(0xFFFFDCC8);
  static const orbPeach = Color(0xFFFFB48A);
  static const orbRose = Color(0xFFFF9A7A);
}

class PetsyRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

/// Consistent spacing scale used across screens.
class PetsySpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;

  static const page = 16.0;
  static const section = 20.0;
  static const listBottom = 28.0;
  static const buttonHeight = 50.0;
}

/// Soft single-layer elevation — prefer these over ad-hoc multi shadows.
class PetsyShadows {
  static List<BoxShadow> get raised => [
        BoxShadow(
          color: PetsyColors.primary.withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get soft => [
        BoxShadow(
          color: PetsyColors.primary.withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get float => [
        BoxShadow(
          color: const Color(0x1A241F1C),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  /// Soft neutral lift for floating action buttons — avoid colored/glowy shadows.
  static List<BoxShadow> get fab => [
        BoxShadow(
          color: const Color(0x1F241F1C),
          blurRadius: 18,
          offset: const Offset(0, 8),
          spreadRadius: -2,
        ),
        BoxShadow(
          color: const Color(0x14241F1C),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
}

/// Tajawal type roles so screens stop inventing one-off sizes.
class PetsyType {
  static TextStyle get display => GoogleFonts.tajawal(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.2,
        color: PetsyColors.text,
      );

  static TextStyle get title => GoogleFonts.tajawal(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.25,
        color: PetsyColors.text,
      );

  static TextStyle get section => GoogleFonts.tajawal(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        height: 1.3,
        color: PetsyColors.text,
      );

  static TextStyle get cardTitle => GoogleFonts.tajawal(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        height: 1.3,
        color: PetsyColors.text,
      );

  static TextStyle get body => GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.45,
        color: PetsyColors.text,
      );

  static TextStyle get subtitle => GoogleFonts.tajawal(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: PetsyColors.textSecondary,
      );

  static TextStyle get meta => GoogleFonts.tajawal(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: PetsyColors.textSecondary,
      );

  static TextStyle get price => GoogleFonts.tajawal(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        height: 1.2,
        color: PetsyColors.primary,
      );

  static TextStyle get button => GoogleFonts.tajawal(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: Colors.white,
      );
}

/// Shell tab canvas gradient.
LinearGradient get petsyShellGradient => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        PetsyColors.background,
        PetsyColors.mist,
        PetsyColors.shellWash,
        PetsyColors.backgroundAlt,
      ],
      stops: [0.0, 0.35, 0.72, 1.0],
    );

/// Light wash for pushed routes (avoids dead flat gray).
LinearGradient get petsyPageGradient => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        PetsyColors.background,
        PetsyColors.backgroundAlt,
      ],
      stops: [0.0, 0.45],
    );

ThemeData buildPetsyTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PetsyColors.primary,
    primary: PetsyColors.primary,
    secondary: PetsyColors.secondary,
    tertiary: PetsyColors.accent,
    error: PetsyColors.error,
    surface: PetsyColors.surface,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: PetsyColors.text,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(PetsyRadius.md),
    borderSide: const BorderSide(color: PetsyColors.border),
  );

  final textTheme = GoogleFonts.tajawalTextTheme().apply(
    bodyColor: PetsyColors.text,
    displayColor: PetsyColors.text,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: PetsyColors.backgroundAlt,
    dividerColor: PetsyColors.border,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      },
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const Icon(
        Icons.arrow_back_ios_new_rounded,
        size: 18,
        color: PetsyColors.text,
      ),
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      backgroundColor: PetsyColors.background.withValues(alpha: 0.96),
      foregroundColor: PetsyColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x14000000),
      titleTextStyle: PetsyType.section.copyWith(fontSize: 18),
      iconTheme: const IconThemeData(color: PetsyColors.text, size: 20),
      actionsIconTheme: const IconThemeData(color: PetsyColors.text, size: 22),
    ),
    cardTheme: CardThemeData(
      color: PetsyColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.lg),
        side: const BorderSide(color: PetsyColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PetsyColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: PetsySpacing.lg, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: PetsyColors.primary, width: 1.5),
      ),
      hintStyle: PetsyType.subtitle.copyWith(fontWeight: FontWeight.w500, color: PetsyColors.textLight),
      labelStyle: PetsyType.meta.copyWith(color: PetsyColors.textSecondary),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: PetsyColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      extendedPadding: const EdgeInsetsDirectional.fromSTEB(14, 0, 18, 0),
      extendedIconLabelSpacing: 10,
      extendedTextStyle: PetsyType.body.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 14.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PetsyColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PetsyColors.primary.withValues(alpha: 0.45),
        // Avoid Size.fromHeight (infinite width) — breaks buttons inside Rows.
        minimumSize: const Size(64, PetsySpacing.buttonHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
        textStyle: PetsyType.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, PetsySpacing.buttonHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: PetsyColors.primaryDark,
        side: BorderSide(color: PetsyColors.primary.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.md)),
        textStyle: PetsyType.button.copyWith(color: PetsyColors.primaryDark),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: PetsyColors.primaryDark,
        textStyle: PetsyType.body.copyWith(fontWeight: FontWeight.w700, color: PetsyColors.primaryDark),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: PetsyColors.surface,
      selectedColor: PetsyColors.primarySoft,
      side: const BorderSide(color: PetsyColors.border),
      labelStyle: PetsyType.meta.copyWith(color: PetsyColors.text, fontWeight: FontWeight.w600),
      secondaryLabelStyle: PetsyType.meta.copyWith(color: PetsyColors.primaryDark, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.xl)),
      padding: const EdgeInsets.symmetric(horizontal: PetsySpacing.sm, vertical: PetsySpacing.xs),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PetsyColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: PetsyColors.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PetsyRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PetsyColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PetsyRadius.xl),
        side: const BorderSide(color: PetsyColors.border),
      ),
      titleTextStyle: PetsyType.section.copyWith(fontSize: 18),
      contentTextStyle: PetsyType.meta.copyWith(
        fontSize: 14,
        height: 1.45,
        color: PetsyColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      contentTextStyle: PetsyType.body.copyWith(
        color: PetsyColors.text,
        fontWeight: FontWeight.w700,
      ),
      insetPadding: const EdgeInsets.fromLTRB(PetsySpacing.page, 0, PetsySpacing.page, PetsySpacing.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PetsyRadius.lg)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: PetsyColors.surface,
      indicatorColor: PetsyColors.primarySoft,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => PetsyType.meta.copyWith(
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? PetsyColors.primaryDark : PetsyColors.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? PetsyColors.primary : PetsyColors.textSecondary,
        ),
      ),
    ),
  );
}
