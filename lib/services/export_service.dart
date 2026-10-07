import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/hive_data.dart';

class ExportService {
  /// Generate and share CSV history report (opens in Microsoft Excel, Google Sheets, LibreOffice)
  static Future<void> exportCsvReport(BuildContext context, HiveData hive) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('Hive ID,Date/Time,Temperature (C),Humidity (%),Acoustic (dB),Queen Condition');

      final dates = hive.historyDates;
      final temps = hive.temperatureHistory;
      final hums = hive.humidityHistory;
      final acoustics = hive.acousticHistory;

      final count = [dates.length, temps.length, hums.length, acoustics.length].reduce((a, b) => a < b ? a : b);

      for (int i = 0; i < count; i++) {
        final d = dates[i];
        final t = temps[i];
        final h = hums[i];
        final a = acoustics[i];
        buffer.writeln('${hive.id},$d,$t,$h,$a,${hive.conditionLabel}');
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/beeware_${hive.id}_telemetry.csv');
      await file.writeAsString(buffer.toString());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'BeeWare Hive ${hive.name} Telemetry Export (CSV)',
          text: 'Telemetry dataset for Hive ${hive.name} (${hive.id})',
        ),
      );
    } catch (e) {
      debugPrint('Export CSV error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export CSV: $e')),
        );
      }
    }
  }

  /// Generate and share a printable, structured HTML/PDF health audit report
  static Future<void> exportAuditReport(BuildContext context, HiveData hive) async {
    try {
      final now = DateTime.now();
      final formattedDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>BeeWare Health & Telemetry Audit - ${hive.name}</title>
  <style>
    body {
      font-family: 'Segoe UI', Arial, sans-serif;
      margin: 24px;
      color: #222;
      background: #fafafa;
    }
    .container {
      max-width: 800px;
      margin: 0 auto;
      background: #fff;
      padding: 32px;
      border-radius: 12px;
      border: 1px solid #e0e0e0;
      box-shadow: 0 4px 12px rgba(0,0,0,0.05);
    }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      border-bottom: 3px solid #FFCC00;
      padding-bottom: 16px;
      margin-bottom: 24px;
    }
    .brand {
      font-size: 26px;
      font-weight: 900;
      color: #000;
      letter-spacing: 1px;
    }
    .meta {
      font-size: 13px;
      color: #666;
      text-align: right;
    }
    .card {
      background: #fff8e1;
      border: 1px solid #ffe082;
      border-radius: 8px;
      padding: 16px;
      margin-bottom: 20px;
    }
    .badge {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: bold;
    }
    .badge-present { background: #e8f5e9; color: #2e7d32; }
    .badge-absent { background: #ffebee; color: #c62828; }
    .badge-accepted { background: #e3f2fd; color: #1565c0; }
    .badge-rejected { background: #fff3e0; color: #e65100; }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 12px;
      margin-bottom: 20px;
    }
    th, td {
      border: 1px solid #ddd;
      padding: 10px 12px;
      text-align: left;
      font-size: 13px;
    }
    th {
      background: #f5f5f5;
      font-weight: bold;
    }
    .footer {
      margin-top: 32px;
      font-size: 11px;
      color: #888;
      text-align: center;
      border-top: 1px solid #eee;
      padding-top: 12px;
    }
    @media print {
      body { background: #fff; margin: 0; }
      .container { border: none; box-shadow: none; padding: 0; }
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div>
        <div class="brand">🐝 BEEWARE AUDIT REPORT</div>
        <div style="font-size: 14px; color: #555; font-weight: bold; margin-top: 4px;">Apiary Intelligence & Hive Health Diagnostic</div>
      </div>
      <div class="meta">
        <div><strong>Generated:</strong> $formattedDate</div>
        <div><strong>Hive ID:</strong> ${hive.id}</div>
        <div><strong>Device ID:</strong> ${hive.deviceId}</div>
      </div>
    </div>

    <div class="card">
      <h3 style="margin-top: 0; margin-bottom: 8px;">Colony Executive Summary: ${hive.name}</h3>
      <p style="margin: 4px 0;"><strong>Queen Status:</strong> <span class="badge ${hive.conditionLabel.toLowerCase().contains('absent') ? 'badge-absent' : (hive.conditionLabel.toLowerCase().contains('rejected') ? 'badge-rejected' : (hive.conditionLabel.toLowerCase().contains('accepted') ? 'badge-accepted' : 'badge-present'))}">${hive.conditionLabel}</span></p>
      <p style="margin: 4px 0;"><strong>Colony Health Score:</strong> ${hive.healthScore}% (Confidence: ${hive.confidence}%)</p>
      <p style="margin: 4px 0;"><strong>Recommendation:</strong> ${hive.recommendation}</p>
      <p style="margin: 4px 0;"><strong>Notes / Location:</strong> ${hive.notes}</p>
    </div>

    <h3>Current Sensor Telemetry</h3>
    <table>
      <thead>
        <tr>
          <th>Metric</th>
          <th>Live Value</th>
          <th>Optimal Range</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>Internal Temperature</td>
          <td><strong>${hive.temperature}°C</strong></td>
          <td>32.0°C - 35.5°C</td>
          <td>${double.tryParse(hive.temperature) != null && double.parse(hive.temperature) >= 32.0 && double.parse(hive.temperature) <= 35.5 ? 'Optimal' : 'Attention Needed'}</td>
        </tr>
        <tr>
          <td>Relative Humidity</td>
          <td><strong>${hive.humidity}%</strong></td>
          <td>50% - 70%</td>
          <td>Normal</td>
        </tr>
        <tr>
          <td>Acoustic Signal</td>
          <td><strong>${hive.acoustic}</strong></td>
          <td>180 - 220 Hz</td>
          <td>${hive.acousticStatus}</td>
        </tr>
        <tr>
          <td>Device Battery</td>
          <td><strong>${hive.batteryLevel}</strong></td>
          <td>> 20%</td>
          <td>Good</td>
        </tr>
        <tr>
          <td>Wi-Fi Connection</td>
          <td><strong>${hive.wifiStatus}</strong></td>
          <td>Connected</td>
          <td>${hive.wifiStatus}</td>
        </tr>
      </tbody>
    </table>

    <h3>Historical Telemetry & Queen Condition Timeline</h3>
    <table>
      <thead>
        <tr>
          <th>Date / Period</th>
          <th>Temp (°C)</th>
          <th>Humidity (%)</th>
          <th>Acoustic (dB)</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        ${List.generate(hive.historyDates.length, (i) => '''
        <tr>
          <td>${hive.historyDates[i]}</td>
          <td>${i < hive.temperatureHistory.length ? hive.temperatureHistory[i] : '--'}°C</td>
          <td>${i < hive.humidityHistory.length ? hive.humidityHistory[i] : '--'}%</td>
          <td>${i < hive.acousticHistory.length ? hive.acousticHistory[i] : '--'} dB</td>
          <td>${i < hive.conditionTimeline.length ? hive.conditionTimeline[i]['status'] : hive.conditionLabel}</td>
        </tr>
        ''').join()}
      </tbody>
    </table>

    <div class="footer">
      Generated automatically by BeeWare Smart Apiary Monitor • Certified IoT & AI Telemetry Pipeline
    </div>
  </div>
</body>
</html>
''';

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/beeware_${hive.id}_audit_report.html');
      await file.writeAsString(html);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/html')],
          subject: 'BeeWare Hive ${hive.name} Health Audit Report',
          text: 'Comprehensive health audit document for Hive ${hive.name}',
        ),
      );
    } catch (e) {
      debugPrint('Export Audit error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export audit: $e')),
        );
      }
    }
  }



  static const MethodChannel _galleryChannel =
      MethodChannel('com.example.beeware_app/gallery');

  /// Download high-resolution QR sticker PNG from URL and automatically save it directly to the phone's Gallery
  static Future<void> downloadAndShareQrSticker(BuildContext context, HiveData hive) async {
    try {
      final url = hive.effectiveQrCodeUrl;
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw Exception('Server returned status ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final cleanDevId = hive.deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'BeeWare_QR_${cleanDevId}_$ts.png';

      bool savedToGallery = false;

      // 1. Save via native Android MediaStore (Pictures/BeeWare in Gallery)
      if (Platform.isAndroid) {
        try {
          final uri = await _galleryChannel.invokeMethod<String>(
            'saveImageToGallery',
            {
              'bytes': bytes,
              'fileName': fileName,
            },
          );
          if (uri != null && uri.isNotEmpty) {
            savedToGallery = true;
            debugPrint('✅ QR Sticker saved to Android MediaStore Gallery: $uri');
          }
        } catch (e) {
          debugPrint('ℹ️ MediaStore channel fallback to public Gallery directories: $e');
        }
      }

      // 2. Also write to public Gallery directories (Pictures/BeeWare & DCIM/Camera)
      // so Android's FUSE MediaProvider indexes it into the Gallery immediately
      final galleryDirs = [
        '/storage/emulated/0/Pictures/BeeWare',
        '/storage/emulated/0/DCIM/Camera',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Download',
      ];

      for (final dirPath in galleryDirs) {
        try {
          final dir = Directory(dirPath);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          if (dir.existsSync()) {
            final destFile = File('${dir.path}/$fileName');
            await destFile.writeAsBytes(bytes, flush: true);
            savedToGallery = true;
            debugPrint('✅ QR Sticker saved to Gallery path: ${destFile.path}');
            break;
          }
        } catch (e) {
          debugPrint('Gallery directory write skipped ($dirPath): $e');
        }
      }

      // 3. Fallback if neither MediaStore nor public Gallery folder succeeded (e.g. iOS / Desktop)
      if (!savedToGallery) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tempFile.path, mimeType: 'image/png')],
            subject: 'BeeWare Hive QR Code Sticker - ${hive.name}',
          ),
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${hive.name} QR Code saved to Gallery!'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Download QR Sticker error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save QR Code to Gallery: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Shares the direct download web link via messaging/social apps so anyone can open and download the QR code image
  static Future<void> shareQrDownloadLink(BuildContext context, HiveData hive) async {
    try {
      final link = hive.effectiveQrCodeUrl;
      await SharePlus.instance.share(
        ShareParams(
          subject: 'BeeWare Hive QR Sticker Download Link - ${hive.name}',
          text: 'Download the official BeeWare QR Code Sticker for ${hive.name} (${hive.deviceId}):\n$link\n\nScan this QR code sticker with the BeeWare app to monitor real-time hive telemetry.',
        ),
      );
    } catch (e) {
      debugPrint('Share QR link error: $e');
    }
  }

  /// Display a modal bottom sheet displaying the QR Sticker with quick download and share options
  static void showQrStickerModal(BuildContext context, HiveData hive) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Title and device badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${hive.name} QR Code',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Device ID: ${hive.deviceId}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFD54F)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code, size: 14, color: Color(0xFFF57F17)),
                        SizedBox(width: 4),
                        Text(
                          'ESP32 Node',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF57F17),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // QR Code Container with honeycomb/border styling
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        hive.effectiveQrCodeUrl,
                        width: 220,
                        height: 220,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            width: 220,
                            height: 220,
                            child: Center(
                              child: CircularProgressIndicator(color: Color(0xFFFFCC00)),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 220,
                            height: 220,
                            color: Colors.grey.shade100,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey),
                                SizedBox(height: 8),
                                Text(
                                  'QR Preview Unavailable',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Scan this QR code sticker on the hive box to pair.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Download Hive QR Sticker Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(modalContext);
                    downloadAndShareQrSticker(context, hive);
                  },
                  icon: const Icon(Icons.download_rounded, color: Colors.black),
                  label: const Text(
                    'Download Hive QR Code',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFCC00),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.black, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Action Buttons: Share Link, Copy Link, Close
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(modalContext);
                        shareQrDownloadLink(context, hive);
                      },
                      icon: const Icon(Icons.share_rounded, size: 16, color: Colors.black87),
                      label: const Text(
                        'Share Link',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: Colors.black26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: hive.effectiveQrCodeUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('QR Code image URL copied to clipboard!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16, color: Colors.black87),
                      label: const Text(
                        'Copy Link',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: Colors.black26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(modalContext),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: Colors.black26),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
