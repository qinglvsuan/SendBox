import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gap/gap.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import '../services/localsender_service.dart';
import '../utils/theme.dart';
import '../src/rust/api/simple.dart' as rust;

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final _textController = TextEditingController();
  bool _isDragging = false;
  bool _serverButtonPressed = false;
  StreamSubscription<rust.UploadRequest>? _uploadReqSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = Provider.of<LocalSenderService>(context, listen: false);
      _uploadReqSub = service.uploadRequestStream.listen(_handleUploadRequest);
    });
  }

  void _handleUploadRequest(rust.UploadRequest req) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('收到文件传输请求'),
        content: Text('文件名: ${req.name}\n大小: ${_formatBytes(req.size)}\n\n是否允许接收该文件？'),
        actions: [
          TextButton(
            onPressed: () {
              rust.resolveUpload(id: req.id, accepted: false);
              Navigator.of(ctx).pop();
            },
            child: const Text('拒绝', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MinimalTheme.primary, foregroundColor: Colors.white),
            onPressed: () {
              rust.resolveUpload(id: req.id, accepted: true);
              Navigator.of(ctx).pop();
            },
            child: const Text('接收'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _uploadReqSub?.cancel();
    _pulseController.dispose();
    _textController.dispose();
    super.dispose();
  }

  String _formatBytes(BigInt sizeInBytes) {
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

  Future<void> _pickAndStageFile(LocalSenderService service) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.path != null) {
            await service.stageFile(file.path!);
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("成功暂存了 ${result.files.length} 个文件"),
              backgroundColor: MinimalTheme.secondary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("暂存文件失败: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _stageClipboardText(LocalSenderService service) async {
    try {
      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
        await service.stageText(data.text!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("已从系统剪贴板暂存文本内容"),
              backgroundColor: MinimalTheme.secondary,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("系统剪贴板中没有文本内容"),
              backgroundColor: Colors.amber,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("暂存文本失败: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _stageCustomText(LocalSenderService service) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    try {
      await service.stageText(text);
      _textController.clear();
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("自定义文本暂存成功"),
            backgroundColor: MinimalTheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("暂存失败: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showTextStagingDialog(LocalSenderService service) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: MinimalTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0x1AFFFFFF)),
          ),
          title: const Text("暂存自定义文本"),
          content: TextField(
            controller: _textController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: "在此输入需要共享的文本内容...",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("取消", style: TextStyle(color: MinimalTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: MinimalTheme.primary),
              onPressed: () => _stageCustomText(service),
              child: const Text("暂存", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<LocalSenderService>(context);

    if (service.isServerRunning) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DropTarget(
        onDragDone: (detail) async {
          if (!service.isServerRunning) return;
          for (final file in detail.files) {
            await service.stageFile(file.path);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("已拖入并暂存 ${detail.files.length} 个文件"),
                backgroundColor: MinimalTheme.secondary,
              ),
            );
          }
        },
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: _isDragging
              ? BoxDecoration(
                  border: Border.all(color: MinimalTheme.primary.withOpacity(0.6), width: 2),
                  borderRadius: BorderRadius.circular(16),
                  color: MinimalTheme.primary.withOpacity(0.05),
                )
              : const BoxDecoration(),
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isDragging)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MinimalTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MinimalTheme.primary.withOpacity(0.4), width: 1.5),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.file_download_rounded, color: MinimalTheme.primary, size: 36),
                    Gap(8),
                    Text("松手即可暂存文件", style: TextStyle(color: MinimalTheme.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
              ).animate().fadeIn(duration: 150.ms),
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
                      "SendBox 暂存服务",
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Gap(8),
                    Text(
                      "将本机的文件或剪贴板内容挂载至局域网，其他设备随时可取",
                      style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
                // Server switch button
                _buildServerToggleButton(service),
              ],
            ),
            const Gap(28),
            
            // Server status card
            _buildServerStatusCard(service),
            const Gap(24),

            if (service.isServerRunning) ...[
              // Action buttons (Add files / text)
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      label: "暂存本地文件",
                      subtitle: "支持拖入或多选文件",
                      icon: Icons.add_to_photos_rounded,
                      color: MinimalTheme.primary,
                      onTap: () => _pickAndStageFile(service),
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    child: _buildActionButton(
                      label: "暂存系统剪贴板",
                      subtitle: "一键共享最新文本",
                      icon: Icons.assignment_returned_rounded,
                      color: MinimalTheme.secondary,
                      onTap: () => _stageClipboardText(service),
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    child: _buildActionButton(
                      label: "手动输入文本",
                      subtitle: "快捷挂载临时备忘",
                      icon: Icons.edit_note_rounded,
                      color: MinimalTheme.accent,
                      onTap: () => _showTextStagingDialog(service),
                    ),
                  ),
                ],
              ),
              const Gap(24),
              // Shared items list header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "当前正在共享的暂存项",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: MinimalTheme.primary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => service.refreshLocalItems(),
                    icon: const Icon(Icons.refresh_rounded, size: 16, color: MinimalTheme.secondary),
                    label: const Text("刷新", style: TextStyle(fontSize: 12, color: MinimalTheme.secondary)),
                  ),
                ],
              ),
              const Gap(12),
              // Staged items list
              service.localItems.isEmpty
                  ? _buildEmptyState().animate().fadeIn()
                  : _buildStagedItemsList(service),
            ] else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 80,
                        color: MinimalTheme.textMuted.withOpacity(0.3),
                      ),
                      const Gap(16),
                      Text(
                        "本地暂存服务器未启动",
                        style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Gap(8),
                      const Text(
                        "点击右上角按钮启动本地服务，开启无感局域网分享",
                        style: TextStyle(color: MinimalTheme.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ).animate().fade().slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildServerToggleButton(LocalSenderService service) {
    final isRunning = service.isServerRunning;
    final bg = isRunning ? Colors.redAccent.withOpacity(0.15) : MinimalTheme.primary;
    final fg = isRunning ? Colors.redAccent : Colors.white;
    final border = isRunning ? BorderSide(color: Colors.redAccent) : BorderSide.none;

    return GestureDetector(
      onTapDown: (_) => setState(() => _serverButtonPressed = true),
      onTapUp: (_) {
        setState(() => _serverButtonPressed = false);
        service.toggleServer(!isRunning).catchError((e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("操作失败: $e"), backgroundColor: Colors.redAccent),
            );
          }
        });
      },
      onTapCancel: () => setState(() => _serverButtonPressed = false),
      child: AnimatedScale(
        scale: _serverButtonPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _serverButtonPressed ? bg.withOpacity(0.7) : bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.fromBorderSide(border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded, color: fg, size: 20),
              const Gap(8),
              Text(
                isRunning ? "关闭服务" : "启动服务",
                style: TextStyle(fontWeight: FontWeight.bold, color: fg, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerStatusCard(LocalSenderService service) {
    final isRunning = service.isServerRunning;
    return Container(
      width: double.infinity,
      decoration: MinimalTheme.glassDecoration(
        color: isRunning ? const Color(0x0C00F5D4) : const Color(0x0AFFFFFF),
        borderColor: isRunning ? MinimalTheme.secondary.withOpacity(0.3) : const Color(0x10FFFFFF),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Pulse Indicator
          if (isRunning)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MinimalTheme.secondary,
                    boxShadow: [
                      BoxShadow(
                        color: MinimalTheme.secondary.withOpacity(0.6),
                        blurRadius: 4 + _pulseController.value * 8,
                        spreadRadius: _pulseController.value * 4,
                      ),
                    ],
                  ),
                );
              },
            )
          else
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: MinimalTheme.textMuted,
              ),
            ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRunning ? "服务正在运行 • 网内广播中" : "服务器已关闭",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isRunning ? MinimalTheme.secondary : MinimalTheme.textSecondary,
                  ),
                ),
                const Gap(4),
                Text(
                  isRunning 
                      ? "节点名: ${service.nodeName}   |   地址: http://${service.serverAddress}" 
                      : "局域网内的其他设备目前将无法发现或连接此设备",
                  style: TextStyle(color: MinimalTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (isRunning)
            IconButton(
              icon: const Icon(Icons.copy_rounded, color: MinimalTheme.textSecondary, size: 20),
              tooltip: "复制基础地址",
              onPressed: () {
                Clipboard.setData(ClipboardData(text: "http://${service.serverAddress}"));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("服务器地址已复制到剪贴板"), backgroundColor: MinimalTheme.primary),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: MinimalTheme.glassDecoration(
          borderColor: color.withOpacity(0.2),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const Gap(16),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Gap(4),
            Text(
              subtitle,
              style: TextStyle(color: MinimalTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        width: double.infinity,
        decoration: MinimalTheme.glassDecoration(),
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.drive_folder_upload_rounded, color: MinimalTheme.textMuted.withOpacity(0.4), size: 48),
            const Gap(16),
            const Text(
              "暂无任何挂载暂存项",
              style: TextStyle(fontWeight: FontWeight.bold, color: MinimalTheme.textSecondary),
            ),
            const Gap(8),
            Text(
              "请点击上方按钮添加您的共享文件或共享剪贴板",
              style: TextStyle(color: MinimalTheme.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStagedItemsList(LocalSenderService service) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: service.localItems.length,
      itemBuilder: (context, index) {
        final item = service.localItems[index];
        final isFile = item.itemType == rust.StagedItemType.file;
        final downloadUrl = isFile 
            ? "http://${service.serverAddress}/files/${item.id}"
            : "http://${service.serverAddress}/clipboard/${item.id}";

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
              item.name,
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
                  _formatBytes(item.size),
                  style: TextStyle(color: MinimalTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Copy Link
                IconButton(
                  tooltip: "复制下载/获取链接",
                  icon: const Icon(Icons.link_rounded, color: MinimalTheme.textSecondary, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: downloadUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("链接已成功复制"), backgroundColor: MinimalTheme.primary),
                    );
                  },
                ),
                // Remove / Unstage
                IconButton(
                  tooltip: "取消暂存",
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    try {
                      await service.unstageItem(item.id);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("暂存项已移除"), backgroundColor: Colors.black87),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("移除失败: $e"), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ).animate(delay: (index * 30).ms).fade(duration: 400.ms).slideX(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
      },
    );
  }
}
