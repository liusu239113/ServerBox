import 'package:dynamic_color/dynamic_color.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:fl_lib/generated/l10n/lib_l10n.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:surlor_ai/core/app_navigator.dart';
import 'package:surlor_ai/core/extension/context/locale.dart';
import 'package:surlor_ai/data/res/build_data.dart';
import 'package:surlor_ai/data/res/store.dart';
import 'package:surlor_ai/generated/l10n/l10n.dart';
import 'package:surlor_ai/view/page/home.dart';

part 'intro.dart';

Widget _buildHomeWithWindowFrame() {
  return VirtualWindowFrame(title: BuildData.name, child: const HomePage());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<List<IntroPageBuilder>> _introFuture = _IntroPage.builders;
  bool _transparentNavBarConfigured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_transparentNavBarConfigured) return;
    _transparentNavBarConfigured = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemUIs.setTransparentNavigationBar(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RNodes.app,
      builder: (context, _) {
        if (!Stores.setting.useSystemPrimaryColor.fetch()) {
          return _build(context);
        }

        return _buildDynamicColor(context);
      },
    );
  }

  Widget _build(BuildContext context) {
    final colorSeed = Color(Stores.setting.colorSeed.fetch());

    UIs.colorSeed = colorSeed;
    UIs.primaryColor = colorSeed;

    return _buildApp(
      context,
      light: _buildLightTheme(colorSeed),
      dark: _buildDarkTheme(colorSeed),
    );
  }

  /// Surlor AI 浅色主题 - 橙色 + 暖灰
  ThemeData _buildLightTheme(Color seed) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      appBarTheme: AppBarTheme(
        scrolledUnderElevation: 0.0,
        backgroundColor: base.surfaceContainerLow,
        foregroundColor: base.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: base.surfaceContainerLow,
        indicatorColor: seed.withOpacity(0.15),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: base.surfaceContainerLow,
        indicatorColor: seed.withOpacity(0.15),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seed,
        foregroundColor: Colors.white,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: base.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: base.surfaceContainerHighest.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: seed, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      chipTheme: ChipThemeData(
        selectedColor: seed.withOpacity(0.2),
        side: BorderSide(color: seed.withOpacity(0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Surlor AI 深色主题 - 终端风格（深灰底 + 橙色高亮）
  ThemeData _buildDarkTheme(Color seed) {
    // 终端风格配色：接近 VS Code / Warp 的暗色调
    final darkBg = const Color(0xFF1E1E1E);       // 终端黑
    const surfaceDark = Color(0xFF252526);       // 表面深色
    const surfaceMid = Color(0xFF2D2D2D);        // 表面中色
    const surfaceHigh = Color(0xFF3C3C3C);       // 表面亮色

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: seed,
        onPrimary: Colors.white,
        secondary: const Color(0xFFFF9500),       // 亮橙辅助色
        surface: surfaceDark,
        onSurface: const Color(0xFFD4D4D4),      // 浅灰文字
        surfaceContainerLowest: darkBg,
        surfaceContainerLow: surfaceDark,
        surfaceContainer: surfaceMid,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: const Color(0xFF4A4A4A),
        error: const Color(0xFFF44336),
        onError: Colors.white,
        outline: const Color(0xFF555555),
        outlineVariant: const Color(0xFF3A3A3A),
        inverseSurface: seed,
      ),
      scaffoldBackgroundColor: darkBg,
      appBarTheme: AppBarTheme(
        scrolledUnderElevation: 0.0,
        backgroundColor: surfaceDark,
        foregroundColor: const Color(0xFFE0E0E0),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        color: surfaceMid,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: const Color(0xFF3A3A3A), width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceDark,
        indicatorColor: seed.withOpacity(0.25),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: Color(0xFFFF8C00), fontWeight: FontWeight.w600);
          }
          return const TextStyle(color: Color(0xFF888888));
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Color(0xFFFF8C00));
          }
          return const IconThemeData(color: Color(0xFF777777));
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceDark,
        indicatorColor: seed.withOpacity(0.25),
        selectedIconTheme: const IconThemeData(color: Color(0xFFFF8C00)),
        unselectedIconTheme: const IconThemeData(color: Color(0xFF666666)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seed,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceMid,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceMid,
        titleTextStyle: const TextStyle(
          color: Color(0xFFE0E0E0),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF3A3A3A)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF444444)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF8C00), width: 1.5),
        ),
        hintStyle: const TextStyle(color: Color(0xFF666666)),
        labelStyle: const TextStyle(color: Color(0xFFFF8C00)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        iconColor: const Color(0xFFAAAAAA),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: seed.withOpacity(0.3),
        side: const BorderSide(color: Color(0xFF555555)),
        labelStyle: const TextStyle(color: Color(0xFFDDDDDD)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFFBBBBBB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(
        color: const Color(0xFF333333),
        thickness: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return seed;
          return const Color(0xFF666666);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return seed.withOpacity(0.5);
          return const Color(0xFF444444);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: seed,
        thumbColor: seed,
        inactiveTrackColor: const Color(0xFF444444),
        overlayColor: seed.withOpacity(0.2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: seed,
        linearTrackColor: const Color(0xFF333333),
        circularTrackColor: const Color(0xFF333333),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF555555)),
        ),
        textStyle: const TextStyle(color: Color(0xFFDDDDDD)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceMid,
        contentTextStyle: const TextStyle(color: Color(0xFFE0E0E0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: seed,
        unselectedItemColor: const Color(0xFF666666),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: seed,
        labelColor: seed,
        unselectedLabelColor: const Color(0xFF777777),
      ),
    );
  }

  Widget _buildDynamicColor(BuildContext context) {
    return DynamicColorBuilder(
      builder: (light, dark) {
        final lightSeed = light?.primary ?? UIs.colorSeed;
        final darkSeed = dark?.primary ?? UIs.colorSeed;

        if (context.isDark && dark != null) {
          UIs.primaryColor = dark.primary;
          UIs.colorSeed = dark.primary;
        } else if (!context.isDark && light != null) {
          UIs.primaryColor = light.primary;
          UIs.colorSeed = light.primary;
        } else {
          final fallbackColor = Color(Stores.setting.colorSeed.fetch());
          UIs.primaryColor = fallbackColor;
          UIs.colorSeed = fallbackColor;
        }

        return _buildApp(
          context,
          light: _buildLightTheme(lightSeed),
          dark: _buildDarkTheme(darkSeed),
        );
      },
    );
  }

  Widget _buildApp(
    BuildContext ctx, {
    required ThemeData light,
    required ThemeData dark,
  }) {
    final tMode = Stores.setting.themeMode.fetch();
    // Issue #57
    final themeMode = switch (tMode) {
      1 || 2 => ThemeMode.values[tMode],
      3 => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final locale = Stores.setting.locale.fetch().toLocale;

    return MaterialApp(
      key: ValueKey(locale),
      restorationScopeId: 'surlor_ai',
      navigatorKey: AppNavigator.key,
      builder: ResponsivePoints.builder,
      locale: locale,
      localizationsDelegates: const [
        LibLocalizations.delegate,
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: LocaleUtil.resolve,
      navigatorObservers: [AppRouteObserver.instance],
      title: BuildData.name,
      themeMode: themeMode,
      theme: light.fixWindowsFont,
      darkTheme: (tMode < 3 ? dark : dark.toAmoled).fixWindowsFont,
      home: FutureBuilder<List<IntroPageBuilder>>(
        future: _introFuture,
        builder: (context, snapshot) {
          context.setLibL10n();
          final appL10n = AppLocalizations.of(context);
          if (appL10n != null) l10n = appL10n;

          Widget child;
          var hasWindowFrame = false;
          if (snapshot.connectionState == ConnectionState.waiting) {
            child = const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else {
            final intros = snapshot.data ?? [];
            if (intros.isNotEmpty) {
              child = _IntroPage(intros);
            } else {
              child = _buildHomeWithWindowFrame();
              hasWindowFrame = true;
            }
          }

          if (hasWindowFrame) return child;
          return VirtualWindowFrame(title: BuildData.name, child: child);
        },
      ),
    );
  }
}
