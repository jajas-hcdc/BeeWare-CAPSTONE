import 'dart:async';
import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/backend_service.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';
import 'hive_detail_screen.dart';
import 'qr_hive_scanner_screen.dart';

class NodeDetectionScreen extends StatefulWidget {
  const NodeDetectionScreen({super.key});

  @override
  State<NodeDetectionScreen> createState() => _NodeDetectionScreenState();
}

class _NodeDetectionScreenState extends State<NodeDetectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _pollingTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Initial telemetry poll to detect already-transmitting nodes
    _pollCloudTelemetry();

    // Actively poll every 3 seconds while on this detection screen
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _pollCloudTelemetry(silent: true);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollCloudTelemetry({bool silent = false}) async {
    if (!silent) {
      setState(() => _isRefreshing = true);
    }
    try {
      final records = await BackendService().fetchTelemetryRecords(limit: 50);
      HiveService().updateFromBackendTelemetry(records);
    } catch (e) {
      debugPrint('Detection polling error: $e');
    } finally {
      if (mounted && !silent) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _showPairDialog(HiveData node) {
    final nameController = TextEditingController(text: node.name);
    final notesController = TextEditingController(text: node.notes);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9C4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.sensors_rounded, color: Colors.black, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pair ${node.deviceId}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assign a friendly name and notes for this hive before adding it to your apiary.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            const Text(
              'Hive Name',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                hintText: 'e.g. Hive 1 - North Orchard',
                filled: true,
                fillColor: const Color(0xFFFFFDE7),
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
            const SizedBox(height: 12),
            const Text(
              'Notes (Optional)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                hintText: 'e.g. Main colony, new queen introduced',
                filled: true,
                fillColor: const Color(0xFFFFFDE7),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
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
              final customName = nameController.text.trim();
              final customNotes = notesController.text.trim();
              Navigator.pop(ctx);
              _completePairing(node, customName, customNotes);
            },
            child: const Text('Pair & Add Hive', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).whenComplete(() {
      nameController.dispose();
      notesController.dispose();
    });
  }

  void _completePairing(HiveData node, String customName, String customNotes) {
    HiveService().pairDiscoveredNode(
      node,
      customName: customName.isNotEmpty ? customName : node.name,
      customNotes: customNotes.isNotEmpty ? customNotes : node.notes,
    );

    final paired = HiveService().getHiveByDeviceId(node.deviceId) ?? node;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 28),
            SizedBox(width: 8),
            Text('Hive Paired!', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${paired.name} (${paired.deviceId}) is now successfully connected to your apiary!',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            const Text(
              'Real-time telemetry and health diagnostics are now streaming to your dashboard.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
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
              Navigator.pop(ctx);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => HiveDetailScreen(hive: paired)),
              );
            },
            child: const Text('Open Hive Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HiveService(),
      builder: (context, _) {
        final unpairedNodes = HiveService().unpairedNodes;

        return Scaffold(
          backgroundColor: AppColors.screenYellow,
          appBar: CustomHeaderBar(
            title: 'Node Detection',
            showBack: true,
            actions: [
              IconButton(
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.black),
                tooltip: 'Refresh cloud telemetry',
                onPressed: () => _pollCloudTelemetry(),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Radar / Status Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color.lerp(
                                const Color(0xFFFFF176),
                                const Color(0xFFFFCC00),
                                _pulseController.value,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFCC00).withValues(
                                    alpha: 0.3 + 0.3 * _pulseController.value,
                                  ),
                                  blurRadius: 10 + 10 * _pulseController.value,
                                  spreadRadius: 2 * _pulseController.value,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(Icons.sensors_rounded, color: Colors.black, size: 28),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Live Detection Phase',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              unpairedNodes.isEmpty
                                  ? 'Listening for active ESP32 nodes transmitting on cloud...'
                                  : '${unpairedNodes.length} active node${unpairedNodes.length > 1 ? "s" : ""} discovered ready to pair!',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Discovered Nodes (${unpairedNodes.length})',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const QrHiveScannerScreen()),
                        );
                      },
                      icon: const Icon(Icons.qr_code_scanner, size: 16, color: Colors.black87),
                      label: const Text(
                        'Scan QR Instead',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // List of Discovered Nodes or Empty State
                if (unpairedNodes.isEmpty)
                  _buildEmptyState()
                else
                  ...unpairedNodes.map((node) => _buildDiscoveredNodeCard(node)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDE7),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFD54F)),
            ),
            child: const Icon(Icons.radar_rounded, size: 40, color: Color(0xFFF57F17)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Waiting for Node Telemetry...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Ensure your ESP32 node is powered on with Wi-Fi credentials.\n'
            '2. The node transmits immediately on boot, and then every 5 minutes.\n'
            '3. Press the EN / RST button on your ESP32 to trigger an instant transmission.',
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () => _pollCloudTelemetry(),
              icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.black),
              label: const Text(
                'Check Cloud Now',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: Colors.black, width: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveredNodeCard(HiveData node) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Device ID badge and status tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9C4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.developer_board_rounded, color: Colors.black, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    node.deviceId,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF81C784)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi, size: 13, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 4),
                    Text(
                      node.updated == 'In Cooldown' ? 'IN COOLDOWN' : 'ACTIVE NODE',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Live Metrics Row
          Row(
            children: [
              _buildMetricChip(Icons.thermostat_rounded, '${node.temperature} °C', 'Temp'),
              const SizedBox(width: 8),
              _buildMetricChip(Icons.water_drop_rounded, '${node.humidity} %', 'Humidity'),
              const SizedBox(width: 8),
              _buildMetricChip(Icons.graphic_eq_rounded, node.acoustic, 'Acoustics'),
              const SizedBox(width: 8),
              _buildMetricChip(Icons.battery_charging_full_rounded, node.batteryLevel, 'Battery'),
            ],
          ),
          const SizedBox(height: 12),

          // Condition Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  node.conditionLabel.contains('Present') ? Icons.check_circle : Icons.warning_rounded,
                  size: 14,
                  color: node.conditionLabel.contains('Present') ? const Color(0xFF2E7D32) : Colors.orange.shade800,
                ),
                const SizedBox(width: 6),
                Text(
                  'Initial AI Condition: ${node.conditionLabel}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Action Buttons: Pair & Preview QR
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: () => _showPairDialog(node),
                    icon: const Icon(Icons.add_link_rounded, color: Colors.black, size: 18),
                    label: const Text(
                      'Pair & Add Hive',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCC00),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Colors.black, width: 1.2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: Colors.black45),
                tooltip: 'Dismiss',
                onPressed: () => HiveService().dismissDiscoveredNode(node.deviceId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: Colors.black87),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
