import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gap/gap.dart';
import '../services/localsender_service.dart';
import '../utils/theme.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _nodeNameController = TextEditingController();
  final _portController = TextEditingController();
  String _downloadPath = "";

  @override
  void initState() {
    super.initState();
    _loadDownloadPath();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = Provider.of<LocalSenderService>(context);
    if (_nodeNameController.text == "SendBoxNode" || _nodeNameController.text.isEmpty) {
      _nodeNameController.text = service.nodeName;
    }
    if (_portController.text.isEmpty) {
      _portController.text = service.port.toString();
    }
  }

  Future<void> _loadDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    String? path = prefs.getString('download_path');
    if (path == null) {
      final downloadsDir = await getDownloadsDirectory();
      path = downloadsDir?.path ?? (await getApplicationDocumentsDirectory()).path;
      await prefs.setString('download_path', path);
    }
    setState(() {
      _downloadPath = path!;
    });
  }

  Future<void> _selectDownloadPath() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('download_path', result);
      setState(() {
        _downloadPath = result;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("下载目录已更改为: $result"),
            backgroundColor: MinimalTheme.primary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<LocalSenderService>(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "软件设置",
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Gap(8),
            const Text(
              "在此自定义您的局域网暂存节点参数与外观",
              style: TextStyle(color: MinimalTheme.textSecondary),
            ),
            const Gap(32),

            // Appearance Settings Section
            _buildSectionTitle("外观配置"),
            const Gap(16),
            Container(
              decoration: MinimalTheme.glassDecoration(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "自定义壁纸",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: MinimalTheme.textPrimary,
                    ),
                  ),
                  const Gap(8),
                  const Text(
                    "选择一张本地图片作为应用的全局背景。",
                    style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 13),
                  ),
                  const Gap(16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MinimalTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          FilePickerResult? result = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                          );
                          if (result != null && result.files.single.path != null) {
                            await service.setCustomWallpaperPath(result.files.single.path);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("已应用自定义壁纸"),
                                backgroundColor: MinimalTheme.secondary,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.image),
                        label: const Text("选择壁纸"),
                      ),
                      const Gap(16),
                      if (service.customWallpaperPath != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                          onPressed: () async {
                            await service.setCustomWallpaperPath(null);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("已清除自定义壁纸"),
                              ),
                            );
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text("清除壁纸"),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const Gap(32),
            
            // Staging Settings Section
            _buildSectionTitle("节点配置"),
            const Gap(16),
            Container(
              decoration: MinimalTheme.glassDecoration(),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Node Name Field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nodeNameController,
                          decoration: const InputDecoration(
                            labelText: "设备节点名称 (Node Name)",
                            hintText: "输入局域网中显示的名称",
                          ),
                        ),
                      ),
                      const Gap(16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MinimalTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final name = _nodeNameController.text.trim();
                          if (name.isNotEmpty) {
                            await service.setNodeName(name);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("节点名称已更新"),
                                backgroundColor: MinimalTheme.secondary,
                              ),
                            );
                          }
                        },
                        child: const Text("保存"),
                      ),
                    ],
                  ),
                  const Gap(20),
                  // Port Field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "服务监听端口 (Port)",
                            hintText: "默认 8080",
                          ),
                        ),
                      ),
                      const Gap(16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MinimalTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final portVal = int.tryParse(_portController.text.trim());
                          if (portVal != null && portVal > 1024 && portVal < 65535) {
                            await service.setPort(portVal);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("端口已修改为 $portVal"),
                                backgroundColor: MinimalTheme.secondary,
                              ),
                            );
                          } else {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("无效端口号 (1025~65534)"),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                        child: const Text("保存"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const Gap(32),
            _buildSectionTitle("存储配置"),
            const Gap(16),
            Container(
              decoration: MinimalTheme.glassDecoration(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "下载存储目录",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: MinimalTheme.textPrimary,
                    ),
                  ),
                  const Gap(8),
                  const Text(
                    "从局域网其他节点下载的文件将保存在此文件夹中：",
                    style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 13),
                  ),
                  const Gap(16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: MinimalTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x1A000000)),
                          ),
                          child: Text(
                            _downloadPath.isEmpty ? "正在加载..." : _downloadPath,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'Consolas',
                              color: MinimalTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const Gap(16),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: MinimalTheme.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _selectDownloadPath,
                        icon: const Icon(Icons.folder_open_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const Gap(40),
            const Center(
              child: Text(
                "SendBox v1.0.0 • Rust & Flutter Power",
                style: TextStyle(color: MinimalTheme.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: MinimalTheme.primary,
      ),
    );
  }

  @override
  void dispose() {
    _nodeNameController.dispose();
    _portController.dispose();
    super.dispose();
  }
}

