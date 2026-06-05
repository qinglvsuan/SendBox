import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gap/gap.dart';
import '../services/localsender_service.dart';
import '../utils/theme.dart';
import 'dashboard_view.dart';
import 'discovery_view.dart';
import 'settings_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentTab = 0;

  final List<Widget> _views = const [
    DashboardView(),
    DiscoveryView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<LocalSenderService>(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    final Widget body = IndexedStack(
      index: _currentTab,
      children: _views,
    );

    // Build the main scaffold with either BottomNavigationBar or NavigationRail
    Widget scaffoldContent;
    if (isMobile) {
      scaffoldContent = Scaffold(
        backgroundColor: Colors.transparent, // Let wallpaper show through
        body: SafeArea(child: body),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (index) => setState(() => _currentTab = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "共享"),
            BottomNavigationBarItem(icon: Icon(Icons.radar_rounded), label: "发现"),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: "设置"),
          ],
        ),
      );
    } else {
      scaffoldContent = Scaffold(
        backgroundColor: Colors.transparent,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: MinimalTheme.surface.withOpacity(0.85),
              selectedIndex: _currentTab,
              onDestinationSelected: (index) => setState(() => _currentTab = index),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(bottom: 24, top: 16),
                child: Icon(
                  Icons.swap_horizontal_circle_rounded,
                  color: MinimalTheme.primary,
                  size: 32,
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Tooltip(
                      message: service.isServerRunning ? "服务运行中: ${service.nodeName}" : "服务已停止",
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: service.isServerRunning ? MinimalTheme.secondary : MinimalTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.dashboard_rounded), label: Text("共享")),
                NavigationRailDestination(icon: Icon(Icons.radar_rounded), label: Text("发现")),
                NavigationRailDestination(icon: Icon(Icons.settings_rounded), label: Text("设置")),
              ],
            ),
            Container(width: 1, color: const Color(0x1A000000)),
            Expanded(child: body),
          ],
        ),
      );
    }

    // Wrap with background if wallpaper is set
    return Container(
      decoration: BoxDecoration(
        color: MinimalTheme.background,
        image: service.customWallpaperPath != null
            ? DecorationImage(
                image: FileImage(File(service.customWallpaperPath!)),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  MinimalTheme.background.withValues(alpha: 0.5), // Lighten the wallpaper slightly
                  BlendMode.lighten,
                ),
              )
            : null,
      ),
      child: scaffoldContent,
    );
  }
}

