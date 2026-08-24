import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _pushNotifications = true;
  bool _alertNotifications = true;

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const Icon(Icons.notifications_none, color: Colors.black, size: 24),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Push Notifications',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Switch(
                    value: _pushNotifications,
                    activeThumbColor: Colors.black,
                    activeTrackColor: const Color(0xFF4A4A4A),
                    onChanged: (val) => setState(() => _pushNotifications = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Alert Notifications Tile
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.black, size: 24),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Alert Notifications',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Switch(
                    value: _alertNotifications,
                    activeThumbColor: Colors.black,
                    activeTrackColor: const Color(0xFF4A4A4A),
                    onChanged: (val) => setState(() => _alertNotifications = val),
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
