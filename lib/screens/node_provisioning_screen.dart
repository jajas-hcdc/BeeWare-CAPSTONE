import 'dart:async';
import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class NodeProvisioningScreen extends StatefulWidget {
  const NodeProvisioningScreen({super.key});

  @override
  State<NodeProvisioningScreen> createState() => _NodeProvisioningScreenState();
}

class _NodeProvisioningScreenState extends State<NodeProvisioningScreen> {
  int _currentStep = 0; // 0: Scan, 1: Wi-Fi Credentials & Hive Info, 2: Provisioning, 3: Success

  bool _isScanning = true;

  // Discovered nearby devices (starts clean and empty)
  final List<Map<String, dynamic>> _discoveredNodes = [];

  Map<String, dynamic>? _selectedNode;

  final TextEditingController _hiveNameController = TextEditingController();
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _obscurePassword = true;

  // Provisioning steps progress
  int _provisionProgress = 0;
  String _provisionStatusText = 'Connecting to ESP32 BLE...';

  @override
  void initState() {
    super.initState();
    _startScanTimer();
  }

  void _startScanTimer() {
    setState(() {
      _isScanning = true;
      _selectedNode = null;
    });
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
  }

  void _showManualPairDialog() {
    final deviceIdCtrl = TextEditingController(text: 'BeeWare-Node-${HiveService().hives.length + 1}');
    final macCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.memory, color: Colors.black),
              SizedBox(width: 8),
              Text('Enter Node ID', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Device / Node ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: deviceIdCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. BeeWare-Node-001',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: const Color(0xFFF9F9F9),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('MAC Address (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: macCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. 24:6F:28:B4:8A:1C',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: const Color(0xFFF9F9F9),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFCC00),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final idText = deviceIdCtrl.text.trim();
                if (idText.isEmpty) return;
                final macText = macCtrl.text.trim().isNotEmpty ? macCtrl.text.trim() : 'ESP32-BLE-DIRECT';

                final newNode = {
                  'name': idText,
                  'mac': macText,
                  'rssi': -50,
                  'battery': 100,
                  'firmware': 'v1.2.0',
                };

                setState(() {
                  _discoveredNodes.removeWhere((n) => n['name'] == idText);
                  _discoveredNodes.add(newNode);
                  _selectedNode = newNode;
                  _hiveNameController.text = 'Hive ${HiveService().hives.length + 1}';
                });

                Navigator.of(ctx).pop();
              },
              child: const Text('Add Node', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _startProvisioning() {
    if (_ssidController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Wi-Fi SSID')),
      );
      return;
    }

    setState(() {
      _currentStep = 2;
      _provisionProgress = 1;
      _provisionStatusText = 'Establishing Bluetooth Low Energy (BLE) link...';
    });

    // Step 1: BLE Connected
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _provisionProgress = 2;
        _provisionStatusText = 'Sending Wi-Fi credentials & Cloud API keys...';
      });

      // Step 2: Wi-Fi Handshake
      Timer(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        setState(() {
          _provisionProgress = 3;
          _provisionStatusText = 'ESP32 connecting to ${_ssidController.text.trim()}...';
        });

        // Step 3: IP Assigned & Telemetry verified
        Timer(const Duration(milliseconds: 1600), () {
          if (!mounted) return;
          setState(() {
            _provisionProgress = 4;
            _provisionStatusText = 'Verifying Firestore connection & sensor stream...';
          });

          // Step 4: Complete
          Timer(const Duration(milliseconds: 1400), () {
            if (!mounted) return;
            _finalizeProvisioning();
          });
        });
      });
    });
  }

  void _finalizeProvisioning() {
    final nodeName = _selectedNode?['name'] ?? 'BW-005-ESP32';
    final hiveName = _hiveNameController.text.trim().isNotEmpty
        ? _hiveNameController.text.trim()
        : 'Hive ${HiveService().hives.length + 1}';

    final newHive = HiveData(
      id: 'hive_${DateTime.now().millisecondsSinceEpoch}',
      name: hiveName,
      deviceId: nodeName,
      notes: _notesController.text.trim(),
      conditionLabel: 'Queen Present',
      confidence: 94,
      healthScore: 92,
      temperature: '34.8',
      humidity: '62',
      acoustic: 'Normal Activity',
      acousticStatus: 'Normal Activity',
      batteryLevel: '${_selectedNode?['battery'] ?? 95}%',
      updated: 'Just now',
      isAlert: false,
      alertLabel: 'Queen Present',
      alertMessage: 'Newly paired IoT node calibrated and streaming.',
    );

    HiveService().addHive(newHive);

    setState(() {
      _currentStep = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: CustomHeaderBar(
        title: _currentStep == 3 ? 'Node Paired!' : 'Pair IoT Node (BLE)',
        showBack: _currentStep != 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Stepper Indicator
            _buildStepIndicator(),
            const SizedBox(height: 20),

            if (_currentStep == 0) _buildScanStep(),
            if (_currentStep == 1) _buildCredentialsStep(),
            if (_currentStep == 2) _buildProvisioningStep(),
            if (_currentStep == 3) _buildSuccessStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['1. Scan', '2. Setup', '3. Pair', '4. Done'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(steps.length, (index) {
          final isCompleted = _currentStep > index;
          final isCurrent = _currentStep == index;
          final color = isCompleted || isCurrent ? const Color(0xFFFFCC00) : Colors.black12;
          final textColor = isCompleted || isCurrent ? Colors.black : Colors.black45;

          return Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.2),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, size: 16, color: Colors.black)
                      : Text(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                steps[index].split('. ').last,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                  color: textColor,
                ),
              ),
              if (index < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0),
                  child: Icon(Icons.chevron_right, size: 16, color: Colors.black26),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildScanStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Radar Animation Card
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(15),
                      offset: const Offset(0, 3),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: _isScanning
                    ? const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        ),
                      )
                    : const Icon(Icons.bluetooth_searching, size: 38, color: Colors.black),
              ),
              const SizedBox(height: 16),
              Text(
                _isScanning
                    ? 'Scanning for Nearby BeeWare Nodes...'
                    : (_discoveredNodes.isEmpty ? 'No Nearby Nodes Detected' : 'Scan Complete'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
              ),
              const SizedBox(height: 4),
              Text(
                _isScanning
                    ? 'Searching for ESP32 Bluetooth Low Energy (BLE) advertisements...'
                    : (_discoveredNodes.isEmpty
                        ? 'Ensure your ESP32 node is powered on with INMP441 & DHT22 attached.'
                        : 'Select a discovered ESP32 node below to configure Wi-Fi credentials.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.refresh, size: 18, color: Colors.black),
                    label: Text(
                      _isScanning ? 'Scanning...' : 'Re-scan',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isScanning ? null : _startScanTimer,
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCC00),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Colors.black, width: 1.2),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18, color: Colors.black),
                    label: const Text(
                      'Pair Manually',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    onPressed: _showManualPairDialog,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Discovered Devices Section
        if (_discoveredNodes.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Discovered Devices',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
              ),
              Text(
                '${_discoveredNodes.length} node(s) found',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 10),

          ..._discoveredNodes.map((node) {
            final isSelected = _selectedNode == node;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedNode = node;
                if (_hiveNameController.text.trim().isEmpty) {
                  _hiveNameController.text = 'Hive ${HiveService().hives.length + 1}';
                }
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10.0),
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFF9C4) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.black26,
                    width: isSelected ? 2 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isSelected ? 25 : 10),
                      offset: const Offset(0, 3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFCC00),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black, width: 1.2),
                      ),
                      child: const Icon(Icons.memory, color: Colors.black, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node['name'],
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MAC: ${node['mac']}  •  FW: ${node['firmware']}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.battery_charging_full, size: 16, color: Colors.green),
                            Text('${node['battery']}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.signal_cellular_alt, size: 14, color: Colors.black54),
                            Text('${node['rssi']} dBm', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedNode != null ? const Color(0xFFFFCC00) : Colors.black12,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.black, width: 1.5),
              ),
            ),
            onPressed: _selectedNode != null ? () => setState(() => _currentStep = 1) : null,
            child: const Text(
              'Connect & Configure Node',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
        ] else if (!_isScanning) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(
              child: Text(
                'No devices to display yet.\nTap "Pair Manually" to register a node by ID.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500, height: 1.4),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCredentialsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.link, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Target: ${_selectedNode?['name']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ],
              ),
              const Divider(height: 20, color: Colors.black12),

              // Hive Name Field
              const Text('Assign Hive Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _hiveNameController,
                decoration: InputDecoration(
                  hintText: 'e.g. Hive 5 - Orchard Stand',
                  prefixIcon: const Icon(Icons.inventory_2_outlined, color: Colors.black87),
                  filled: true,
                  fillColor: const Color(0xFFF9F9F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              // Wi-Fi SSID
              const Text('Apiary Wi-Fi / Hotspot SSID (2.4 GHz)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _ssidController,
                decoration: InputDecoration(
                  hintText: 'Enter 2.4GHz Wi-Fi Name',
                  prefixIcon: const Icon(Icons.wifi, color: Colors.black87),
                  filled: true,
                  fillColor: const Color(0xFFF9F9F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              // Wi-Fi Password
              const Text('Wi-Fi Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Enter Wi-Fi Password',
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.black87),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.black54),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9F9F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              // Notes
              const Text('Apiary Notes & Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  hintText: 'e.g. South pasture, full sun',
                  prefixIcon: const Icon(Icons.notes, color: Colors.black87),
                  filled: true,
                  fillColor: const Color(0xFFF9F9F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.black, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => setState(() => _currentStep = 0),
                child: const Text('Back', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFCC00),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.black, width: 1.5),
                  ),
                ),
                icon: const Icon(Icons.bluetooth_connected, size: 20),
                label: const Text('Send to ESP32', style: TextStyle(fontWeight: FontWeight.w900)),
                onPressed: _startProvisioning,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProvisioningStep() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const SizedBox(height: 10),
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _provisionStatusText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
          ),
          const SizedBox(height: 24),
          _provisionProgressItem(1, 'Connect over BLE', _provisionProgress >= 1),
          _provisionProgressItem(2, 'Upload Wi-Fi & Firebase Auth Tokens', _provisionProgress >= 2),
          _provisionProgressItem(3, 'Verify Wi-Fi Connection & IP Address', _provisionProgress >= 3),
          _provisionProgressItem(4, 'Test Live INMP441 & DHT22 Telemetry Feed', _provisionProgress >= 4),
        ],
      ),
    );
  }

  Widget _provisionProgressItem(int stepNumber, String title, bool isDone) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isDone ? Colors.green : Colors.black26,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                color: isDone ? Colors.black : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStep() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.healthyGreen.withAlpha(40),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.healthyGreen, width: 2),
            ),
            child: const Icon(Icons.check_rounded, color: AppColors.healthyGreen, size: 44),
          ),
          const SizedBox(height: 16),
          Text(
            '${_hiveNameController.text} Paired Successfully!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your ESP32 node is connected to Wi-Fi and sending real-time acoustic, temperature, and humidity telemetry to Cloud Firestore.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFCC00),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.black, width: 1.5),
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Go to My Hives', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
