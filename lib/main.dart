import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:localsender/src/rust/frb_generated.dart';
import 'package:localsender/src/rust/api/simple.dart' as rust;
import 'services/localsender_service.dart';
import 'utils/theme.dart';
import 'views/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Desktop Window Properties
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1020, 680),
      minimumSize: Size(400, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: "SendBox - 局域网暂存箱",
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize flutter_rust_bridge Rust core library
  await RustLib.init();
  
  // Initialize Rust core with temporary directory
  final tempDir = await getTemporaryDirectory();
  await rust.initCore(tempDir: tempDir.path);

  runApp(
    ChangeNotifierProvider(
      create: (_) => LocalSenderService(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SendBox',
      debugShowCheckedModeBanner: false,
      theme: MinimalTheme.lightTheme,
      home: const HomePage(),
    );
  }
}
