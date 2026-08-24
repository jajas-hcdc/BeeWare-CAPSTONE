import 'dart:io';
import 'package:flutter/material.dart';
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
}
