import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/hive_data.dart';
import '../services/hive_service.dart';
import '../services/backend_service.dart';
import 'hive_detail_screen.dart';

/// QR Code scanner that reads an ESP32 hive sticker and directly connects
/// the device to the app without any Bluetooth/BLE or multi-step wizard.
///
/// Supported QR content formats:
///   JSON  → {"deviceId":"BW-XXXXXX","mac":"AA:BB:CC:DD:EE:FF"}
///   Plain → BW-XXXXXX
class QrHiveScannerScreen extends StatefulWidget {
  const QrHiveScannerScreen({super.key});

  @override
  State<QrHiveScannerScreen> createState() => _QrHiveScannerScreenState();
}

class _QrHiveScannerScreenState extends State<QrHiveScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _scanned = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;

    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _scanned = true);
    _cameraController.stop();

    String deviceId = raw.trim();
    String? mac;

    // Try JSON parse first
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      deviceId = (map['deviceId'] ?? map['device_id'] ?? raw).toString().trim();
      mac = map['mac']?.toString();
    } catch (_) {
      // Not JSON — treat the raw value as plain device ID
    }

    if (!mounted) return;
    await _handleDirectQrConnection(deviceId, mac);
  }

  Future<void> _handleDirectQrConnection(String deviceId, String? mac) async {
    final existingMatches = HiveService().hives.where(
      (h) => h.deviceId.toUpperCase() == deviceId.toUpperCase(),
    ).toList();

    if (existingMatches.isNotEmpty) {
      final existingHive = existingMatches.first;
      if (!mounted) return;
      _showExistingHiveDialog(existingHive);
      return;
    }

    // Query backend telemetry for this node to grab real-time live data
    final records = await BackendService().fetchTelemetryRecords(limit: 50);
    final matchingRecords = records.where((r) {
      final dev = (r['device_id'] ?? r['deviceId'] ?? '').toString().toUpperCase();
      return dev == deviceId.toUpperCase();
    }).toList();

    final hiveCount = HiveService().hives.length;
    final defaultHiveName = 'Hive ${hiveCount + 1}';

    HiveData newHive;

    if (matchingRecords.isNotEmpty) {
      final latest = matchingRecords.first;
      final temp = (latest['temperature'] as num?)?.toDouble() ?? 34.0;
      final hum = (latest['humidity'] as num?)?.toDouble() ?? 60.0;
      final batt = (latest['battery_level'] as num?)?.toInt() ?? 100;
      final rssi = (latest['wifi_rssi'] as num?)?.toInt() ?? -65;
      final audioPath = latest['audio_file_path'] as String?;

      int signalBars = 4;
      if (rssi >= -60) {
        signalBars = 4;
      } else if (rssi >= -70) {
        signalBars = 3;
      } else if (rssi >= -80) {
        signalBars = 2;
      } else {
        signalBars = 1;
      }

      final tempHist = matchingRecords
          .map((r) => (r['temperature'] as num?)?.toDouble() ?? 34.0)
          .take(10)
          .toList()
          .reversed
          .toList();
      final humHist = matchingRecords
          .map((r) => (r['humidity'] as num?)?.toDouble() ?? 60.0)
          .take(10)
          .toList()
          .reversed
          .toList();

      final rawFreq = latest['frequency'] ?? latest['frequency_hz'];
      int freqHz = 0;
      if (rawFreq is num) {
        freqHz = rawFreq.toInt();
      } else if (rawFreq is String) {
        freqHz = int.tryParse(rawFreq.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      }
      final acousticStr = freqHz > 0 ? '$freqHz Hz' : '0 Hz';
      final acousticStatusStr = freqHz > 0 ? 'Normal' : 'Not Detected (0 Hz)';

      newHive = HiveData(
        id: 'hive_${DateTime.now().millisecondsSinceEpoch}',
        name: defaultHiveName,
        deviceId: deviceId,
        notes: mac != null && mac.isNotEmpty
            ? 'Paired directly via QR sticker ($mac)'
            : 'Paired directly via QR sticker',
        conditionLabel: 'Queen Present',
        confidence: 95,
        healthScore: 94,
        temperature: temp.toStringAsFixed(1),
        humidity: hum.toStringAsFixed(0),
        acoustic: acousticStr,
        acousticStatus: acousticStatusStr,
        wifiStatus: 'Connected',
        batteryLevel: '$batt%',
        updated: 'Just now',
        signalBars: signalBars,
        audioFilePath: audioPath,
        temperatureHistory: tempHist.isNotEmpty ? tempHist : [temp],
        humidityHistory: humHist.isNotEmpty ? humHist : [hum],
        isAlert: false,
        alertLabel: 'Queen Present',
        alertMessage: 'Direct QR pairing connected to $deviceId.',
      );
    } else {
      newHive = HiveData(
        id: 'hive_${DateTime.now().millisecondsSinceEpoch}',
        name: defaultHiveName,
        deviceId: deviceId,
        notes: mac != null && mac.isNotEmpty
            ? 'Paired directly via QR sticker ($mac)'
            : 'Paired directly via QR sticker',
        conditionLabel: 'Connecting',
        confidence: 0,
        healthScore: 100,
        temperature: '--',
        humidity: '--',
        acoustic: '0 Hz',
        acousticStatus: 'Not Detected (0 Hz)',
        wifiStatus: 'Connected',
        batteryLevel: '100%',
        updated: 'Connecting...',
        signalBars: 4,
        temperatureHistory: const [],
        humidityHistory: const [],
        acousticHistory: const [],
        isAlert: false,
        alertLabel: 'Device Paired',
        alertMessage: 'ESP32 paired directly via QR code. Awaiting sensor stream.',
      );
    }

    HiveService().addHive(newHive);
    BackendService().startTelemetryPolling();

    if (!mounted) return;
    _showPairingSuccessModal(newHive, mac);
  }

  void _showPairingSuccessModal(HiveData hive, String? mac) {
    final nameController = TextEditingController(text: hive.name);

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.black, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withAlpha(30),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                    ),
                    child: const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 34),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Hive Connected Directly!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your ESP32 node is now paired via QR Code. No Bluetooth or manual setup required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F9F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Device ID', style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
                          Text(hive.deviceId, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black)),
                        ],
                      ),
                      if (mac != null && mac.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('MAC Address', style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
                            Text(mac, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Hive Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black87)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'Enter hive name...',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.black, width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.black, width: 1.8),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFCC00),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.black, width: 1.2),
                    ),
                  ),
                  onPressed: () {
                    final trimmedName = nameController.text.trim();
                    final updatedHive = trimmedName.isNotEmpty && trimmedName != hive.name
                        ? hive.copyWith(name: trimmedName)
                        : hive;
                    if (updatedHive != hive) {
                      HiveService().updateHive(updatedHive);
                    }
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => HiveDetailScreen(hive: updatedHive)),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dashboard_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Open Hive Dashboard', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    final trimmedName = nameController.text.trim();
                    if (trimmedName.isNotEmpty && trimmedName != hive.name) {
                      HiveService().updateHive(hive.copyWith(name: trimmedName));
                    }
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop(); // Back to hives screen
                  },
                  child: const Text('Back to Hives', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showExistingHiveDialog(HiveData existingHive) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.black, width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFFFFCC00), size: 24),
              SizedBox(width: 8),
              Text('Hive Already Connected', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          content: Text(
            'The device ID "${existingHive.deviceId}" is already paired as "${existingHive.name}".',
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Back to Hives', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFCC00),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.black, width: 1.2),
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => HiveDetailScreen(hive: existingHive)),
                );
              },
              child: const Text('Open Hive', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Scan Hive QR Code',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: _torchOn ? const Color(0xFFFFCC00) : Colors.white54,
            ),
            tooltip: 'Toggle torch',
            onPressed: () {
              _cameraController.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera feed
          MobileScanner(
            controller: _cameraController,
            onDetect: _onDetect,
          ),

          // Overlay with scanning frame
          _ScannerOverlay(),

          // Bottom hint card
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withAlpha(217),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.qr_code_scanner,
                      color: Color(0xFFFFCC00), size: 32),
                  const SizedBox(height: 10),
                  const Text(
                    'Point camera at the QR sticker\non your BeeWare hive node',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The sticker is on the ESP32 enclosure.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withAlpha(140),
                      fontSize: 12,
                    ),
                  ),
                  if (_scanned) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(
                      color: Color(0xFFFFCC00),
                      strokeWidth: 2.5,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom scanner overlay with a centered crop window and corner brackets.
class _ScannerOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.maxWidth * 0.68;
      final centerX = constraints.maxWidth / 2;
      final centerY = constraints.maxHeight / 2 - 40;

      return CustomPaint(
        painter: _OverlayPainter(
          centerX: centerX,
          centerY: centerY,
          cropSize: size,
        ),
      );
    });
  }
}

class _OverlayPainter extends CustomPainter {
  final double centerX;
  final double centerY;
  final double cropSize;

  const _OverlayPainter({
    required this.centerX,
    required this.centerY,
    required this.cropSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = Colors.black.withAlpha(158);
    final cropRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: cropSize,
      height: cropSize,
    );

    // Dim the area outside the scan window
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(RRect.fromRectAndRadius(cropRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    // Animated-looking corner brackets
    const bracketLen = 28.0;
    const bracketW = 3.5;
    final bracketPaint = Paint()
      ..color = const Color(0xFFFFCC00)
      ..strokeWidth = bracketW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final corners = [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ];

    for (final corner in corners) {
      final dx = corner.dx == cropRect.left ? 1 : -1;
      final dy = corner.dy == cropRect.top ? 1 : -1;
      canvas.drawLine(corner, corner + Offset(dx * bracketLen, 0), bracketPaint);
      canvas.drawLine(corner, corner + Offset(0, dy * bracketLen), bracketPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.centerX != centerX ||
      old.centerY != centerY ||
      old.cropSize != cropSize;
}
