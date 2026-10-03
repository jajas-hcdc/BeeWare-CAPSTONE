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
          ],
        ),
      ),
    );
  }
}
