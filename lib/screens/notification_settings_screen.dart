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
  bool _isTesting = false;

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

  Future<void> _handleTestNotification() async {
    setState(() => _isTesting = true);
    await _alertService.triggerTestAlert();
    if (mounted) {
      setState(() => _isTesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.black, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Test notification triggered successfully! Check your notification banner above.',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryYellow,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pushEnabled = _alertService.pushEnabled;
    final alertsEnabled = _alertService.alertsEnabled;

    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: const CustomHeaderBar(
        title: 'Notification Settings',
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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

            // Diagnostic & Test Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.network_check_rounded, color: Colors.black, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Notification System Status',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildStatusRow('Service', 'Firebase Cloud Messaging (FCM)', Icons.cloud_done_rounded, Colors.green),
                  const SizedBox(height: 6),
                  _buildStatusRow('Topic Channel', 'environment_alerts', Icons.campaign_rounded, Colors.black87),
                  const SizedBox(height: 6),
                  _buildStatusRow('Android Priority', 'High (Urgent Banner & Sound)', Icons.priority_high_rounded, Colors.orange),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryYellow,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.black, width: 2),
                        ),
                      ),
                      onPressed: _isTesting ? null : _handleTestNotification,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.black)),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isTesting ? 'Sending Test Alert...' : 'Send Test Notification',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                      ),
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

  Widget _buildStatusRow(String label, String value, IconData icon, Color iconColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
