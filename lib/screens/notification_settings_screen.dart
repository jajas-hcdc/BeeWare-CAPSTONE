import 'package:flutter/material.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final AlertService _alertService = AlertService();

  @override
  void initState() {
    super.initState();
    _alertService.addListener(_onServiceChange);
  }

  @override
  void dispose() {
    _alertService.removeListener(_onServiceChange);
    super.dispose();
  }

  void _onServiceChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pushEnabled = _alertService.pushEnabled;
    final alertsEnabled = _alertService.alertsEnabled;

    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: const CustomHeaderBar(
        title: 'Notification',
        showBack: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          children: [
            // Push Notifications Tile
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryYellow.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_active_outlined, color: Colors.black, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Push Notifications',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Receive high-priority alerts via Firebase Cloud Messaging',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: pushEnabled,
                    activeThumbColor: Colors.black,
                    activeTrackColor: const Color(0xFF4A4A4A),
                    onChanged: (val) => _alertService.setPushEnabled(val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Alert Notifications Tile
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alert Notifications',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'In-app anomaly banners for temperature, humidity, acoustics',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: alertsEnabled,
                    activeThumbColor: Colors.black,
                    activeTrackColor: const Color(0xFF4A4A4A),
                    onChanged: (val) => _alertService.setAlertsEnabled(val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Test Pop-up Notification Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: const Color(0xFFFFCC00),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.notifications_active, size: 20),
                label: const Text(
                  'Send Test Pop-Up Notification',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                onPressed: () async {
                  await _alertService.triggerTestAlert();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🔔 Pop-up alert dispatched to your phone and Render backend!'),
                        duration: Duration(seconds: 3),
                        backgroundColor: Colors.black87,
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 16),

            // Render Cloud Backend Status Card
            Container(
              padding: const EdgeInsets.all(14.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_done_rounded, color: Color(0xFF2E7D32), size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Render Cloud Push Engine',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Connected to Render FastAPI backend service. Real-time IoT anomalies trigger native system notifications with sound and drop-down banners on your phone.',
                    style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link, size: 12, color: Colors.black45),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'https://beeware-capstone-bu85.onrender.com',
                            style: TextStyle(fontSize: 10, color: Colors.black87, fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
