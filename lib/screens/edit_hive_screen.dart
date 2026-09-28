import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/hive_service.dart';
import '../services/backend_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class EditHiveScreen extends StatefulWidget {
  final HiveData? hive; // If null, Add mode; if provided, Edit mode

  const EditHiveScreen({super.key, this.hive});

  @override
  State<EditHiveScreen> createState() => _EditHiveScreenState();
}

class _EditHiveScreenState extends State<EditHiveScreen> {
  late TextEditingController _nameController;
  late TextEditingController _deviceIdController;
  late TextEditingController _notesController;
  bool _isLoading = false;

  bool get isEdit => widget.hive != null;

  @override
  void initState() {
    super.initState();
    final hiveCount = HiveService().hives.length;
    _nameController = TextEditingController(text: widget.hive?.name ?? 'Hive ${hiveCount + 1}');
    _deviceIdController = TextEditingController(
      text: widget.hive?.deviceId ?? (hiveCount == 0 ? 'BW-001-ALPHA' : 'BW-00${hiveCount + 1}-ALPHA'),
    );
    _notesController = TextEditingController(text: widget.hive?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _deviceIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveHive() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);

    final deviceId = _deviceIdController.text.trim().isEmpty
        ? 'BW-00${HiveService().hives.length + 1}-ALPHA'
        : _deviceIdController.text.trim();

    if (isEdit) {
      final updatedHive = widget.hive!.copyWith(
        name: name,
        deviceId: deviceId,
        notes: _notesController.text.trim(),
      );
      HiveService().updateHive(updatedHive);
    } else {
      // Query backend records to attach real-time live data if available
      final records = await BackendService().fetchTelemetryRecords(limit: 50);
      final matchingRecords = records.where((r) {
        final dev = (r['device_id'] ?? r['deviceId'] ?? '').toString().toUpperCase();
        return dev == deviceId.toUpperCase();
      }).toList();

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
          name: name,
          deviceId: deviceId,
          notes: _notesController.text.trim(),
          conditionLabel: 'Queen Present',
          confidence: 95,
          healthScore: 95,
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
          alertMessage: 'Node registered and telemetry active for $deviceId.',
        );
      } else {
        newHive = HiveData(
          id: 'hive_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          deviceId: deviceId,
          notes: _notesController.text.trim(),
          conditionLabel: 'Connecting',
          confidence: 0,
          healthScore: 100,
          temperature: '--',
          humidity: '--',
          acoustic: '0 Hz',
          acousticStatus: 'Not Detected (0 Hz)',
          wifiStatus: 'Connected',
          batteryLevel: '--%',
          updated: 'Connecting...',
          signalBars: 4,
          temperatureHistory: const [],
          humidityHistory: const [],
          acousticHistory: const [],
          isAlert: false,
          alertLabel: 'Device Registered',
          alertMessage: 'Node registered. Awaiting initial sensor stream.',
        );
      }

      HiveService().addHive(newHive);
      BackendService().startTelemetryPolling();
    }

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEdit ? 'Hive updated successfully!' : 'Hive added with real-time sync!'),
          backgroundColor: Colors.black87,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  void _removeHive() {
    if (!isEdit) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 1.5),
        ),
        title: const Text('Remove Hive?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove ${widget.hive!.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.btnRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.black, width: 1),
              ),
            ),
            onPressed: () {
              HiveService().deleteHive(widget.hive!.id);
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context, true); // Close screen
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: CustomHeaderBar(
        title: isEdit ? widget.hive!.name : 'Add Hive',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black, size: 28),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const EditHiveScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Hive Name',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w600),
              decoration: AppStyles.inputDecoration(hintText: 'Hive 1'),
            ),
            const SizedBox(height: 16),

            const Text(
              'Device ID',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _deviceIdController,
              style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w600),
              decoration: AppStyles.inputDecoration(hintText: '(Device ID)'),
            ),
            const SizedBox(height: 16),

            const Text(
              'Notes (Optional)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, color: Colors.black),
              decoration: AppStyles.inputDecoration(hintText: 'Notes on this'),
            ),
            const SizedBox(height: 24),

            // Save Button
            AppStyles.primaryButton(
              text: 'Save',
              isLoading: _isLoading,
              onPressed: _saveHive,
            ),
            const SizedBox(height: 12),

            // Remove Button (only in edit mode)
            if (isEdit)
              AppStyles.primaryButton(
                text: 'Remove',
                backgroundColor: AppColors.btnRed,
                textColor: Colors.black,
                onPressed: _removeHive,
              ),
          ],
        ),
      ),
    );
  }
}
