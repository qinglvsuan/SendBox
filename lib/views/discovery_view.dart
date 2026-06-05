import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:gap/gap.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/localsender_service.dart';
import '../utils/theme.dart';
import '../src/rust/api/simple.dart' as rust;

class DiscoveryView extends StatefulWidget {
  const DiscoveryView({super.key});

  @override
  State<DiscoveryView> createState() => _DiscoveryViewState();
}

class _DiscoveryViewState extends State<DiscoveryView> {
  rust.DiscoveredService? _selectedDevice;
  bool _isLoadingRemoteDetails = false;
  List<dynamic> _remoteItems = [];
  final _manualIpController = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Proactively start scanning on page load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = Provider.of<LocalSenderService>(context, listen: false);
      service.startScanning();
      service.refreshReceivedItems();
    });
    
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        Provider.of<LocalSenderService>(context, listen: false).refreshReceivedItems();
      }
    });
  }

  @override
  void deactivate() {
    // Stop scanning and timer when leaving the view
    Provider.of<LocalSenderService>(context, listen: false).stopScanning();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    // Restart periodic refresh when returning to this view
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        Provider.of<LocalSenderService>(context, listen: false).refreshReceivedItems();
      }
    });
  }

  @override
  void dispose() {
    _manualIpController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _connectManualIp() {
    final ip = _manualIpController.text.trim();
    if (ip.isEmpty) return;

    String host = ip;
    int port = 8080;
    if (ip.contains(':')) {
       final parts = ip.split(':');
       host = parts[0];
       port = int.tryParse(parts[1]) ?? 8080;
    }

    final device = rust.DiscoveredService(
      id: "manual_$ip",
      nodeName: "指定节点 ($host)",
      ip: host,
      port: port,
    );
    
    // Close keyboard
    FocusManager.instance.primaryFocus?.unfocus();
    _fetchRemoteDetails(device);
  }

  String _formatBytes(num sizeInBytes) {
    double bytes = sizeInBytes.toDouble();
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = 0;
    while (bytes >= 1024 && i < suffixes.length - 1) {
      bytes /= 1024;
      i++;
    }
    return "${bytes.toStringAsFixed(1)} ${suffixes[i]}";
  }

  Future<void> _fetchRemoteDetails(rust.DiscoveredService device) async {
    setState(() {
      _selectedDevice = device;
      _isLoadingRemoteDetails = true;
      _remoteItems = [];
    });
    
    try {
      final response = await http
          .get(Uri.parse("http://${device.ip}:${device.port}/info"))
          .timeout(const Duration(seconds: 4));
      
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _remoteItems = data['files'] ?? [];
        });
      } else {
        throw Exception("Server returned code ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("无法获取设备内容 (连接超时或被防火墙拦截)"),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() {
          _selectedDevice = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRemoteDetails = false;
        });
      }
    }
  }

  Future<void> _fetchAndCopyRemoteText(rust.DiscoveredService device, String itemId) async {
    try {
      final response = await http
          .get(Uri.parse("http://${device.ip}:${device.port}/clipboard/$itemId"))
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final text = utf8.decode(response.bodyBytes);
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("已复制远程剪贴板文本到您的系统剪贴板"),
              backgroundColor: MinimalTheme.secondary,
            ),
          );
        }
      } else {
        throw Exception("获取失败");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("复制失败: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _downloadRemoteFile(
    rust.DiscoveredService device, 
    String fileId, 
    String filename, 
    LocalSenderService service
  ) async {
    final prefs = await SharedPreferences.getInstance();
    String? saveDir = prefs.getString('download_path');
    if (saveDir == null) {
      if (Platform.isAndroid) {
        saveDir = '/storage/emulated/0/Download';
      } else {
        final downloadsDir = await getDownloadsDirectory();
        saveDir = downloadsDir?.path ?? (await getApplicationDocumentsDirectory()).path;
      }
    }
    
    final url = "http://${device.ip}:${device.port}/files/$fileId";
    
    try {
      await service.downloadRemoteFile(url, filename, saveDir);
      if (mounted) {
        final fullPath = p.join(saveDir, filename);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("下载完成: $filename"),
            backgroundColor: MinimalTheme.secondary,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: "打开",
              textColor: MinimalTheme.background,
              onPressed: () {
                OpenFilex.open(fullPath);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("下载失败: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<LocalSenderService>(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    Widget leftPanel = _buildLeftPanel(context, service);
    Widget rightPanel = _buildRightDetailPanel(service);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: isMobile
          ? SingleChildScrollView(
              child: Column(
                children: [
                  leftPanel,
                  rightPanel,
                  _buildReceivedItemsPanel(service),
                ],
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: SingleChildScrollView(child: leftPanel)),
                Container(width: 1, color: const Color(0x10FFFFFF)),
                Expanded(flex: 5, child: SingleChildScrollView(child: Column(children: [rightPanel, _buildReceivedItemsPanel(service)]))),
              ],
            ),
    );
  }

  Widget _buildLeftPanel(BuildContext context, LocalSenderService service) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "探索局域网",
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Gap(8),
                  Text(
                    "自动寻找同一局域网中运行 SendBox 的节点",
                    style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
              // Search control button
              _buildScanToggleButton(service),
            ],
          ),
          const Gap(16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualIpController,
                  decoration: InputDecoration(
                    hintText: "手动输入 IP:端口 (例: 192.168.1.5:8080)",
                    hintStyle: TextStyle(color: MinimalTheme.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0x06FFFFFF),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const Gap(8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MinimalTheme.primary.withOpacity(0.15),
                  foregroundColor: MinimalTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _connectManualIp,
                child: const Text("连接"),
              ),
            ],
          ),
          const Gap(28),
          
          // Scanning animation
          if (service.isScanning && service.discoveredDevices.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SpinKitDoubleBounce(
                      color: MinimalTheme.primary,
                      size: 60,
                    ),
                    const Gap(24),
                    Text(
                      "正在静默搜寻局域网设备...",
                      style: TextStyle(color: MinimalTheme.textSecondary, fontWeight: FontWeight.bold),
                    ),
                    const Gap(8),
                    const Text(
                      "请确保其他设备已开启 SendBox 暂存服务，且在同一 Wi-Fi 下",
                      style: TextStyle(color: MinimalTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ).animate().fade().scale(curve: Curves.easeOutBack)
          else if (service.discoveredDevices.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.radar_rounded, color: MinimalTheme.textMuted.withOpacity(0.3), size: 72),
                    const Gap(16),
                    const Text(
                      "未启动扫描或未发现设备",
                      style: TextStyle(color: MinimalTheme.textSecondary, fontWeight: FontWeight.bold),
                    ),
                    const Gap(8),
                    const Text(
                      "点击右上角按钮开始搜寻周围设备",
                      style: TextStyle(color: MinimalTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ).animate().fade()
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: service.discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = service.discoveredDevices[index];
                final isSelected = _selectedDevice?.id == device.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: MinimalTheme.glassDecoration(
                    color: isSelected ? const Color(0x187000FF) : const Color(0x06FFFFFF),
                    borderColor: isSelected ? MinimalTheme.primary : const Color(0x10FFFFFF),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isSelected ? MinimalTheme.primary : MinimalTheme.secondary).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.devices_rounded,
                        color: isSelected ? MinimalTheme.primary : MinimalTheme.secondary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      device.nodeName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      "${device.ip}:${device.port}",
                      style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 11),
                    ),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? MinimalTheme.primary : MinimalTheme.primary.withOpacity(0.1),
                        foregroundColor: isSelected ? Colors.white : MinimalTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(60, 32),
                      ),
                      onPressed: () => _fetchRemoteDetails(device),
                      child: const Text("提取内容", style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ).animate(delay: (index * 50).ms).fade().slideX(begin: -0.05, end: 0);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildScanToggleButton(LocalSenderService service) {
    return service.isScanning
        ? ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: MinimalTheme.primary.withOpacity(0.1),
              foregroundColor: MinimalTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: MinimalTheme.primary),
              ),
            ),
            onPressed: () => service.stopScanning(),
            icon: const SpinKitRing(color: MinimalTheme.primary, size: 16, lineWidth: 2),
            label: const Text("扫描中", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        : ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: MinimalTheme.secondary,
              foregroundColor: MinimalTheme.background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => service.startScanning(),
            icon: const Icon(Icons.search_rounded),
            label: const Text("开始搜寻", style: TextStyle(fontWeight: FontWeight.bold)),
          );
  }

  Widget _buildRightDetailPanel(LocalSenderService service) {
    if (_selectedDevice == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.layers_clear_rounded, color: MinimalTheme.textMuted.withOpacity(0.3), size: 64),
            const Gap(16),
            Text(
              "未选择目标设备",
              style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const Gap(8),
            const Text(
              "请在左侧列表中点击“提取内容”查看该设备挂载的暂存项",
              style: TextStyle(color: MinimalTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_isLoadingRemoteDetails) {
      return const Center(
        child: SpinKitFadingCircle(
          color: MinimalTheme.primary,
          size: 40,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "暂存列表: ${_selectedDevice!.nodeName}",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: MinimalTheme.textPrimary),
                  ),
                  const Gap(4),
                  Text(
                    "主机地址: ${_selectedDevice!.ip}:${_selectedDevice!.port}",
                    style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: MinimalTheme.textSecondary),
                onPressed: () {
                  setState(() {
                    _selectedDevice = null;
                  });
                },
              ),
            ],
          ),
          const Gap(24),
          _remoteItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_rounded, color: MinimalTheme.textMuted.withOpacity(0.3), size: 48),
                        const Gap(16),
                        const Text(
                          "该节点当前未挂载任何内容",
                          style: TextStyle(fontWeight: FontWeight.bold, color: MinimalTheme.textSecondary),
                        ),
                        const Gap(8),
                        Text(
                          "让对方将文件放入暂存箱后，点击上方重新加载",
                          style: TextStyle(color: MinimalTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ).animate().fade()
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _remoteItems.length,
                  itemBuilder: (context, index) {
                      final item = _remoteItems[index];
                      final isFile = item['item_type'] == 'File';
                      final id = item['id'] as String;
                      final name = item['name'] as String;
                      final size = item['size'] as num;
                      
                      final fileUrl = "http://${_selectedDevice!.ip}:${_selectedDevice!.port}/files/$id";
                      final downloadProgress = service.downloadProgress[fileUrl];
                      final isDownloading = downloadProgress != null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: MinimalTheme.glassDecoration(
                          color: const Color(0x06FFFFFF),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isFile 
                                      ? MinimalTheme.primary.withOpacity(0.15)
                                      : MinimalTheme.secondary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isFile ? Icons.insert_drive_file_rounded : Icons.notes_rounded,
                                  color: isFile ? MinimalTheme.primary : MinimalTheme.secondary,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    isFile ? "文件" : "剪贴板文本",
                                    style: TextStyle(
                                      color: isFile ? MinimalTheme.primary : MinimalTheme.secondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const Text(" • ", style: TextStyle(color: MinimalTheme.textMuted)),
                                  Text(
                                    _formatBytes(size),
                                    style: TextStyle(color: MinimalTheme.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                              trailing: isFile
                                  ? (isDownloading
                                      ? Container(
                                          width: 32,
                                          height: 32,
                                          alignment: Alignment.center,
                                          child: SpinKitRing(color: MinimalTheme.secondary, size: 20, lineWidth: 2.5),
                                        )
                                      : IconButton.filledTonal(
                                          style: IconButton.styleFrom(
                                            backgroundColor: MinimalTheme.primary.withOpacity(0.15),
                                            foregroundColor: MinimalTheme.primary,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          icon: const Icon(Icons.download_rounded, size: 20),
                                          onPressed: () => _downloadRemoteFile(_selectedDevice!, id, name, service),
                                        ))
                                  : IconButton.filledTonal(
                                      style: IconButton.styleFrom(
                                        backgroundColor: MinimalTheme.secondary.withOpacity(0.15),
                                        foregroundColor: MinimalTheme.secondary,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.copy_rounded, size: 20),
                                      onPressed: () => _fetchAndCopyRemoteText(_selectedDevice!, id),
                                    ),
                            ),
                            // Download progress indicator
                            if (isDownloading)
                              ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                                child: LinearProgressIndicator(
                                  value: downloadProgress,
                                  backgroundColor: Colors.transparent,
                                  color: MinimalTheme.primary.withOpacity(0.5),
                                  minHeight: 2,
                                ),
                              ),
                          ],
                        ),
                      ).animate(delay: (index * 30).ms).fade(duration: 400.ms).slideX(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
                    },
                  ),
        ],
      ),
    );
  }

  Widget _buildReceivedItemsPanel(LocalSenderService service) {
    if (service.receivedItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "来自 Web 端的接收箱",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: MinimalTheme.textPrimary),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: MinimalTheme.textSecondary),
                onPressed: () {
                  service.refreshReceivedItems();
                },
              ),
            ],
          ),
          const Gap(16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: service.receivedItems.length,
            itemBuilder: (context, index) {
              final item = service.receivedItems[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: MinimalTheme.glassDecoration(
                  color: const Color(0x06FFFFFF),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: MinimalTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.file_download_done_rounded,
                      color: MinimalTheme.primary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    _formatBytes(item.size.toInt()),
                    style: TextStyle(color: MinimalTheme.textMuted, fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: MinimalTheme.primary.withOpacity(0.15),
                          foregroundColor: MinimalTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.save_alt_rounded, size: 20),
                        onPressed: () => service.downloadReceivedItem(item, context),
                      ),
                      const Gap(8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                        onPressed: () => service.removeReceivedItem(item.id),
                      ),
                    ],
                  ),
                ),
              ).animate(delay: (index * 30).ms).fade(duration: 400.ms).slideX(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
            },
          ),
        ],
      ),
    );
  }
}
