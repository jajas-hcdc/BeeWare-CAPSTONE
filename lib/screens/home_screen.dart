import 'dart:io';
import 'package:flutter/material.dart';
import '../services/hive_service.dart';
import '../services/user_profile_service.dart';
import '../services/alert_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/circular_gauge.dart';
import 'alert_details_screen.dart';
import 'overall_health_assessment_screen.dart';
import 'user_profile_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback? onOpenAlerts;

  const HomeScreen({super.key, this.onOpenAlerts});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HiveService(),
      builder: (context, child) {
        final allHives = HiveService().hives;
        final totalHives = allHives.length;

        // Count statistics for condition summary
        int queenPresentCount = allHives.where((h) => h.conditionLabel.toLowerCase().contains('present')).length;
        int queenAbsentCount = allHives.where((h) => h.conditionLabel.toLowerCase().contains('absent')).length;
        int queenAcceptedCount = allHives.where((h) => h.conditionLabel.toLowerCase().contains('accepted')).length;
        int queenRejectedCount = allHives.where((h) => h.conditionLabel.toLowerCase().contains('rejected')).length;

        final avgHealthScore = totalHives > 0
            ? (allHives.fold<int>(0, (sum, h) => sum + h.healthScore) / totalHives).round()
            : 0;
        final avgConfidence = totalHives > 0
            ? (allHives.fold<int>(0, (sum, h) => sum + h.confidence) / totalHives).round()
            : 0;
        final healthyHivesCount = queenPresentCount + queenAcceptedCount;
        final isOverallHealthy = totalHives > 0 && avgHealthScore >= 80 && queenAbsentCount == 0 && queenRejectedCount == 0;
        final healthColor = totalHives == 0
            ? Colors.black38
            : (avgHealthScore >= 80
                ? AppColors.healthyGreen
                : (avgHealthScore >= 60 ? const Color(0xFFFF9800) : Colors.red));

        // Calculate aggregate apiary environmental metrics
        double totalTemp = 0;
        int validTempCount = 0;
        double totalHum = 0;
        int validHumCount = 0;
        bool hasAcousticAnomaly = false;
        for (final h in allHives) {
          final t = double.tryParse(h.temperature.replaceAll(RegExp(r'[^0-9.]'), ''));
          if (t != null) {
            totalTemp += t;
            validTempCount++;
          }
          final hum = double.tryParse(h.humidity.replaceAll(RegExp(r'[^0-9.]'), ''));
          if (hum != null) {
            totalHum += hum;
            validHumCount++;
          }
          if (h.acousticStatus.toLowerCase().contains('elevated') || h.acousticStatus.toLowerCase().contains('swarming') || h.acousticStatus.toLowerCase().contains('abnormal')) {
            hasAcousticAnomaly = true;
          }
        }
        final avgTempStr = validTempCount > 0 ? (totalTemp / validTempCount).toStringAsFixed(1) : '--';
        final avgHumStr = validHumCount > 0 ? (totalHum / validHumCount).toStringAsFixed(0) : '--';
        final apiaryAcoustic = totalHives == 0 ? 'No Data' : (hasAcousticAnomaly ? 'Elevated\nActivity' : 'Normal\nActivity');

        return Scaffold(
          backgroundColor: AppColors.screenYellow,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          color: Colors.white,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'BEEWARE',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Image.asset(
                        'assets/images/bee_icon.png',
                        height: 24,
                        width: 24,
                        errorBuilder: (context, error, stackTrace) =>
                            const Text('🐝', style: TextStyle(fontSize: 18)),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: onOpenAlerts,
                    child: AnimatedBuilder(
                      animation: AlertService(),
                      builder: (context, child) {
                        final count = AlertService().alerts.length;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.notifications_none, size: 28, color: Colors.black),
                            if (count > 0)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white, width: 1.2),
                                  ),
                                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                  child: Text(
                                    count > 99 ? '99+' : '$count',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: Colors.black,
        backgroundColor: const Color(0xFFFFCC00),
        onRefresh: () async {
          await ConnectivityService().checkConnection();
          if (ConnectivityService().isOnline) {
            await HiveService().refreshFromCloud();
            await AlertService().refreshFromCloud();
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dynamic Offline Banner if network is down
              AnimatedBuilder(
                animation: ConnectivityService(),
                builder: (context, _) {
                  final isOnline = ConnectivityService().isOnline;
                  if (isOnline) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFF9800), width: 1.4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off_rounded, color: Color(0xFFE65100), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Offline Mode',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFFE65100)),
                              ),
                              Text(
                                'Showing cached data (${ConnectivityService().lastSyncedFormatted})',
                                style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            await ConnectivityService().checkConnection();
                            if (ConnectivityService().isOnline) {
                              await HiveService().refreshFromCloud();
                              await AlertService().refreshFromCloud();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9800),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Greeting & User Profile Image Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Dynamic Greeting row with Nickname
                        AnimatedBuilder(
                          animation: UserProfileService(),
                          builder: (context, child) {
                            final nick = UserProfileService().nickname.trim();
                            final name = nick.isNotEmpty ? nick : 'Beekeeper';
                            final hour = DateTime.now().hour;
                            String timeGreeting = 'Good Morning';
                            if (hour >= 12 && hour < 18) {
                              timeGreeting = 'Good Afternoon';
                            } else if (hour >= 18) {
                              timeGreeting = 'Good Evening';
                            }
                            return Text(
                              '$timeGreeting, $name!',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 3),
                        AnimatedBuilder(
                          animation: ConnectivityService(),
                          builder: (context, _) {
                            final isOnline = ConnectivityService().isOnline;
                            final syncText = isOnline
                                ? 'Last updated: ${ConnectivityService().lastSyncedFormatted}'
                                : 'Offline (${ConnectivityService().lastSyncedFormatted})';
                            return Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isOnline ? AppColors.healthyGreen : const Color(0xFFFF9800),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  syncText,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 12),

                // User Profile Image in the encircled top-right area
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const UserProfileScreen()),
                    );
                  },
                  child: AnimatedBuilder(
                    animation: UserProfileService(),
                    builder: (context, child) {
                      final avatar = UserProfileService().selectedAvatar;
                      final customPath = UserProfileService().customImagePath;
                      return Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.black, width: 1.8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(20),
                              offset: const Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Center(
                          child: _buildHomeAvatarWidget(avatar, customPath),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 1: AI Colony Overall Health Assessment
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const OverallHealthAssessmentScreen(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: AppStyles.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'AI Colony Health Assessment',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        Row(
                          children: const [
                            Text(
                              'View All',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.black54,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.arrow_forward_ios, size: 10, color: Colors.black45),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        CircularGauge(
                          percentage: avgHealthScore.toDouble(),
                          size: 78,
                          strokeWidth: 9,
                          progressColor: healthColor,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                totalHives == 0
                                    ? 'No Hives Connected'
                                    : (isOverallHealthy ? 'Healthy!' : 'Attention Needed!'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: totalHives == 0 ? Colors.black87 : healthColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                totalHives == 0
                                    ? 'Pair an IoT Node to begin'
                                    : '$healthyHivesCount of $totalHives Hives Healthy',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                totalHives == 0
                                    ? 'AI Multi-Sensor Ready'
                                    : 'AI Confidence: $avgConfidence%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Section 2: Hive Condition Summary
            const Text(
              'Hive Condition Summary',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _conditionCard(
                    title: 'Queen Present',
                    count: queenPresentCount.toString(),
                    icon: Icons.check_circle_outline,
                    iconColor: AppColors.queenPresentGreen,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _conditionCard(
                    title: 'Queen Absent',
                    count: queenAbsentCount.toString(),
                    icon: Icons.error_outline,
                    iconColor: AppColors.queenAbsentRed,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _conditionCard(
                    title: 'Queen Accepted',
                    count: queenAcceptedCount.toString(),
                    icon: Icons.task_alt,
                    iconColor: AppColors.queenAcceptedBlue,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _conditionCard(
                    title: 'Queen Rejected',
                    count: queenRejectedCount.toString(),
                    icon: Icons.cancel_outlined,
                    iconColor: AppColors.queenRejectedOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Section 3: Current Sensor Data
            const Text(
              'Current Sensor Data',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _sensorCard(
                    title: 'Temperature',
                    icon: Icons.thermostat,
                    iconColor: Colors.black87,
                    value: '$avgTempStr°C',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const OverallHealthAssessmentScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sensorCard(
                    title: 'Humidity',
                    icon: Icons.water_drop_outlined,
                    iconColor: const Color(0xFF64B5F6),
                    value: '$avgHumStr%',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const OverallHealthAssessmentScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sensorCard(
                    title: 'Acoustic Signal',
                    icon: Icons.show_chart,
                    iconColor: const Color(0xFFFFB300),
                    value: apiaryAcoustic,
                    isSmallValue: true,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const OverallHealthAssessmentScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Section 4: Recent Alerts
            const Text(
              'Recent Alerts',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: AlertService(),
              builder: (context, _) {
                final recentAlerts = AlertService().recentAlerts;
                if (recentAlerts.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(12)),
                    child: const Center(
                      child: Text(
                        'All hives are operating normally. No active alerts.',
                        style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                }

                return Column(
                  children: recentAlerts.map((alert) {
                    final isCritical = alert.severity.toLowerCase() == 'critical';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: _alertTile(
                        hiveName: alert.hiveId,
                        alertText: alert.title,
                        timeText: alert.timeFormatted,
                        isCritical: isCritical,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => AlertDetailsScreen(data: alert),
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
},
);
}

  Widget _conditionCard({
    required String title,
    required String count,
    required IconData? icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
      decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            count,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          if (icon != null)
            Icon(icon, size: 18, color: iconColor)
          else
            const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _sensorCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String value,
    bool isSmallValue = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(10.0),
        decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Icon(icon, size: 28, color: iconColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: isSmallValue ? 11 : 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertTile({
    required String hiveName,
    required String alertText,
    required String timeText,
    required bool isCritical,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: isCritical ? Colors.red : const Color(0xFFFFB300),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                  children: [
                    TextSpan(
                      text: '$hiveName  ',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    TextSpan(
                      text: alertText,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              timeText,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeAvatarWidget(String key, String? customPath) {
    if (key == 'custom' && customPath != null && File(customPath).existsSync()) {
      return ClipOval(
        child: Image.file(
          File(customPath),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      );
    }
    switch (key) {
      case 'mascot':
        return ClipOval(
          child: Image.asset(
            'assets/images/bee_mascot_large.png',
            width: 38,
            height: 38,
            fit: BoxFit.contain,
          ),
        );
      case 'bee':
        return ClipOval(
          child: Image.asset(
            'assets/images/bee_icon.png',
            width: 34,
            height: 34,
            fit: BoxFit.contain,
          ),
        );
      case 'farmer':
        return const Icon(Icons.agriculture_rounded, size: 28, color: Colors.black);
      case 'male':
        return const Icon(Icons.face_rounded, size: 30, color: Colors.black);
      case 'female':
        return const Icon(Icons.face_3_rounded, size: 30, color: Colors.black);
      default:
        return const Icon(Icons.person_outline, size: 28, color: Colors.black);
    }
  }
}
