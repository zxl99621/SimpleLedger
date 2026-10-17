import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'styles/tokens.dart';

class BeeTheme {
  // SimpleLedger palette - "Ink & Teal"
  // 青绿色极简账页：薄荷纸底、深青主色、珊瑚红只用于支出金额。
  static const Color teal = Color(0xFF0E7369); // 主色（亮色模式）
  static const Color tealDark = Color(0xFF64CDBF); // 主色（暗色模式）
  static const Color paper = Color(0xFFF4F8F7); // 页面背景（亮色）
  static const Color ink = Color(0xFF132220); // 主文字（亮色）
  static const Color brick = Color(0xFFC2574A); // 支出/警示信号色
  static const Color inkBackgroundDark = Color(0xFF0E1615); // 页面背景（暗色）
  static const Color inkSurfaceDark = Color(0xFF182220); // 卡片/浮层（暗色）

  // Legacy BeeCount brand colors —— 仅遗留皮肤/定制模块引用，新代码不要使用。
  static const Color honeyGold = Color(0xFFF8C91C);
  static const Color hiveBrown = Color(0xFF8D6E63);
  static const Color energyOrange = Color(0xFFEF6C00);
  static const Color paperIvory = Color(0xFFFFF8E1);
  static const Color textDark = ink;

  static const Color honeyGoldDark = honeyGold;
  static const Color hiveBrownDark = hiveBrown;
  static const Color energyOrangeDark = energyOrange;

  static ThemeData lightTheme({TargetPlatform? platform}) {
    final base = ThemeData.light();
    final pf = platform ?? defaultTargetPlatform;
    final isIOS = pf == TargetPlatform.iOS || pf == TargetPlatform.macOS;
    final adjustedTextTheme =
        BeeTypography.buildBase(base.textTheme, isIOS: isIOS)
            .apply(bodyColor: textDark, displayColor: textDark);

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: teal,
        secondary: brick,
        surface: Colors.white,
        onSurface: ink,
      ),
      primaryColor: teal,
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0.0,
        centerTitle: true,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: teal,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: teal,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        backgroundColor: Colors.transparent, // 悬浮胶囊样式，外层透明
        elevation: 0,
      ),
      textTheme: adjustedTextTheme,
    );
  }

  static ThemeData darkTheme({TargetPlatform? platform}) {
    final base = ThemeData.dark();
    final pf = platform ?? defaultTargetPlatform;
    final isIOS = pf == TargetPlatform.iOS || pf == TargetPlatform.macOS;
    final adjusted = BeeTypography.buildBase(base.textTheme, isIOS: isIOS)
        .apply(bodyColor: Colors.white, displayColor: Colors.white);

    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: tealDark,
        onPrimary: inkBackgroundDark,
        primaryContainer: tealDark,
        onPrimaryContainer: inkBackgroundDark,
        secondary: brick,
        surface: inkSurfaceDark,
        onSurface: const Color(0xFFECEFEA),
      ),
      primaryColor: tealDark,
      scaffoldBackgroundColor: inkBackgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: inkBackgroundDark,
        foregroundColor: Color(0xFFECEFEA),
        elevation: 0.0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Color(0xFFECEFEA)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: tealDark,
        foregroundColor: inkBackgroundDark,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: tealDark,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        backgroundColor: Colors.transparent, // 悬浮胶囊样式，外层透明
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: inkSurfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.12), // ⭐ 白色分割线
        thickness: 1,
      ),
      iconTheme: const IconThemeData(
        color: Colors.white,
      ),
      textTheme: adjusted,
    );
  }
}
