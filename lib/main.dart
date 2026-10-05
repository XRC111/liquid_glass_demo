import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:liquid_glass_demo/glass/glass.dart';
import 'pages/card_demo.dart';
import 'pages/home_page.dart';
import 'pages/tabbar_demo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  // 1. 加载片元着色器（构建期已由工具链编译为 Vulkan SPIR-V + GLSL ES 双目标）
  final shaders = await GlassShaderProgram.load();

  // 2. 设备能力检测 -> 自动质量分级
  //    API 29+ -> full / API 26-28 -> medium / API 24-25 或低内存 -> minimal
  final profile = await GlassDeviceProfile.detect();

  runApp(LiquidGlassDemoApp(shaders: shaders, profile: profile));
}

class LiquidGlassDemoApp extends StatelessWidget {
  const LiquidGlassDemoApp({
    super.key,
    required this.shaders,
    required this.profile,
  });

  final GlassShaderProgram shaders;
  final GlassDeviceProfile profile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liquid Glass Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF667EEA),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0E12),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => HomePage(profile: profile),
        '/tabs': (context) => TabBarDemo(profile: profile),
        '/cards': (context) => CardDemo(profile: profile),
      },
    );
  }
}
