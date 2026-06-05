import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';
import '../src/rust/api/simple.dart' as rust;

class LocalSenderService extends ChangeNotifier {
  bool _isServerRunning = false;
  String _serverAddress = "";
  String _nodeName = "SendBoxNode";
  int _port = 8080;
  List<rust.StagedItem> _localItems = [];
  List<rust.StagedItem> _receivedItems = [];
  String? _customWallpaperPath;
  
  bool _isScanning = false;
  final List<rust.DiscoveredService> _discoveredDevices = [];
  StreamSubscription<rust.DiscoveredService>? _discoverySubscription;
  StreamSubscription<rust.UploadRequest>? _uploadSubscription;
  final _uploadRequestController = StreamController<rust.UploadRequest>.broadcast();

  // Track download progress for different file URLs. Key: URL, Value: Progress (0.0 to 1.0)
  final Map<String, double> _downloadProgress = {};

  bool get isServerRunning => _isServerRunning;
  String get serverAddress => _serverAddress;
  String get nodeName => _nodeName;
  int get port => _port;
  List<rust.StagedItem> get localItems => _localItems;
  List<rust.StagedItem> get receivedItems => _receivedItems;
  String? get customWallpaperPath => _customWallpaperPath;
  
  bool get isScanning => _isScanning;
  List<rust.DiscoveredService> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  Map<String, double> get downloadProgress => _downloadProgress;
  Stream<rust.UploadRequest> get uploadRequestStream => _uploadRequestController.stream;

  LocalSenderService() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedName = prefs.getString('node_name');
    if (savedName == null || savedName == "SendBoxNode") {
      savedName = await _getDefaultNodeName();
      await prefs.setString('node_name', savedName);
    }
    _nodeName = savedName;
    
    _port = prefs.getInt('server_port') ?? 8080;
    _customWallpaperPath = prefs.getString('custom_wallpaper_path');
    rust.cleanCache();
    notifyListeners();
  }

  Future<String> _getDefaultNodeName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return '${info.brand} - ${info.model}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return '${info.name} - ${info.model}';
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        final osName = info.productName.isNotEmpty ? info.productName : 'Windows';
        return '${info.computerName} - $osName';
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        return '${info.computerName} - ${info.model}';
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        return '${Platform.localHostname} - ${info.prettyName}';
      }
    } catch (e) {
      // fallback
    }
    return "SendBox_${Platform.operatingSystem}";
  }

  Future<void> setNodeName(String name) async {
    _nodeName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('node_name', name);
    notifyListeners();
    if (_isServerRunning) {
      // Restart server to apply name change to mDNS
      await toggleServer(true);
    }
  }

  Future<void> setPort(int newPort) async {
    _port = newPort;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('server_port', newPort);
    notifyListeners();
    if (_isServerRunning) {
      // Restart server to bind to new port
      await toggleServer(true);
    }
  }

  Future<void> setCustomWallpaperPath(String? path) async {
    _customWallpaperPath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('custom_wallpaper_path');
    } else {
      await prefs.setString('custom_wallpaper_path', path);
    }
    notifyListeners();
  }


  Future<void> toggleServer(bool isRunning) async {
    try {
      if (isRunning) {
        final address = await rust.startServer(port: _port, name: _nodeName);
        _serverAddress = address;
        _isServerRunning = true;
        
        _uploadSubscription?.cancel();
        _uploadSubscription = rust.startUploadListener().listen((req) {
          _uploadRequestController.add(req);
        });
        
        await refreshLocalItems();
      } else {
        await rust.stopServer();
        _uploadSubscription?.cancel();
        _uploadSubscription = null;
        
        _isServerRunning = false;
        _serverAddress = "";
        _localItems.clear();
      }
    } catch (e) {
      debugPrint("Error toggling server: $e");
      _isServerRunning = false;
      _serverAddress = "";
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> refreshLocalItems() async {
    if (!_isServerRunning) return;
    try {
      _localItems = await rust.getStagedItems();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching staged items: $e");
    }
  }

  Future<void> refreshReceivedItems() async {
    _receivedItems = await rust.getReceivedItems();
    notifyListeners();
  }

  Future<void> removeReceivedItem(String id) async {
    try {
      await rust.removeReceivedItem(id: id);
      await refreshReceivedItems();
    } catch (e) {
      debugPrint("Failed to remove received item: $e");
    }
  }

  Future<void> downloadReceivedItem(rust.StagedItem item, BuildContext context) async {
    try {
      if (item.path == null) return;
      
      final sourceFile = File(item.path!);
      if (!await sourceFile.exists()) {
        throw Exception("源文件已丢失");
      }

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          downloadsDir = Directory(p.join(externalDir.path, 'Download'));
          if (!await downloadsDir.exists()) await downloadsDir.create(recursive: true);
        }
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null) {
        throw Exception("无法获取下载目录");
      }

      final targetPath = p.join(downloadsDir.path, item.name);
      await sourceFile.copy(targetPath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("已保存到下载目录: ${item.name}"),
            backgroundColor: MinimalTheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("保存失败: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> stageFile(String path) async {
    if (!_isServerRunning) return;
    try {
      await rust.stageFile(path: path);
      await refreshLocalItems();
    } catch (e) {
      debugPrint("Error staging file: $e");
      rethrow;
    }
  }

  Future<void> stageText(String text) async {
    if (!_isServerRunning) return;
    try {
      await rust.stageText(text: text);
      await refreshLocalItems();
    } catch (e) {
      debugPrint("Error staging text: $e");
      rethrow;
    }
  }

  Future<void> unstageItem(String id) async {
    try {
      await rust.unstageItem(id: id);
      await refreshLocalItems();
    } catch (e) {
      debugPrint("Error unstaging item: $e");
      rethrow;
    }
  }

  void startScanning() {
    if (_isScanning) return;
    _discoveredDevices.clear();
    _isScanning = true;
    notifyListeners();

    try {
      final stream = rust.startDiscovery();
      _discoverySubscription = stream.listen((device) {
        // Avoid duplicate entries
        if (!_discoveredDevices.any((d) => d.id == device.id)) {
          _discoveredDevices.add(device);
          notifyListeners();
        }
      }, onError: (e) {
        debugPrint("mDNS scan error: $e");
        stopScanning();
      });
    } catch (e) {
      debugPrint("Failed to start mDNS scan: $e");
      stopScanning();
    }
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    _isScanning = false;
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    try {
      await rust.stopDiscovery();
    } catch (e) {
      debugPrint("Error stopping discovery: $e");
    }
    notifyListeners();
  }

  Future<void> downloadRemoteFile(String url, String filename, String saveDir) async {
    final savePath = p.join(saveDir, filename);
    _downloadProgress[url] = 0.0;
    notifyListeners();

    double lastNotified = 0.0;
    try {
      final stream = rust.downloadFile(url: url, savePath: savePath);
      await for (final progress in stream) {
        _downloadProgress[url] = progress;
        // Throttle UI updates: notify every 2% or on completion
        if ((progress - lastNotified).abs() >= 0.02 || progress >= 1.0) {
          lastNotified = progress;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Download error: $e");
      _downloadProgress.remove(url);
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    _uploadSubscription?.cancel();
    _uploadRequestController.close();
    rust.stopServer().catchError((e) => debugPrint("dispose stopServer: $e"));
    rust.stopDiscovery().catchError((e) => debugPrint("dispose stopDiscovery: $e"));
    super.dispose();
  }
}
