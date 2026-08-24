import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/circular_gauge.dart';
import '../widgets/custom_app_bar.dart';
import 'hive_detail_screen.dart';

class OverallHealthAssessmentScreen extends StatelessWidget {
  const OverallHealthAssessmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HiveService(),
      builder: (context, child) {
        final hives = HiveService().hives;

        final totalHives = hives.length;
        final presentCount = hives.where((h) => h.conditionLabel.contains('Present')).length;
        final absentCount = hives.where((h) => h.conditionLabel.contains('Absent')).length;
        final acceptedCount = hives.where((h) => h.conditionLabel.contains('Accepted')).length;
        final rejectedCount = hives.where((h) => h.conditionLabel.contains('Rejected')).length;
        final healthyCount = presentCount + acceptedCount;

        final avgHealthScore = totalHives > 0
            ? (hives.fold<int>(0, (sum, h) => sum + h.healthScore) / totalHives).round()
            : 0;
        final avgConfidence = totalHives > 0
            ? (hives.fold<int>(0, (sum, h) => sum + h.confidence) / totalHives).round()
            : 0;

        // Calculate average temp and humidity
        double totalTemp = 0;
        int validTempCount = 0;
        double totalHum = 0;
        int validHumCount = 0;
        for (final h in hives) {
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
        }
        final avgTempStr = validTempCount > 0 ? (totalTemp / validTempCount).toStringAsFixed(1) : '--';
        final avgHumStr = validHumCount > 0 ? (totalHum / validHumCount).toStringAsFixed(0) : '--';

        final isOverallHealthy = totalHives > 0 && avgHealthScore >= 80 && absentCount == 0 && rejectedCount == 0;
        final healthColor = totalHives == 0
            ? Colors.black38
            : (avgHealthScore >= 80
                ? AppColors.healthyGreen
                : (avgHealthScore >= 60 ? const Color(0xFFFF9800) : Colors.red));

        return Scaffold(
          backgroundColor: AppColors.screenYellow,
          appBar: const CustomHeaderBar(
            title: 'Apiary Health Assessment',
            showBack: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Apiary Overall Score Card
                Container(
                  padding: const EdgeInsets.all(18.0),
                  decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Overall Apiary Colony Health',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          CircularGauge(
                            percentage: avgHealthScore.toDouble(),
                            size: 84,
                            strokeWidth: 10,
                            progressColor: healthColor,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isOverallHealthy ? 'Healthy Apiary!' : 'Attention Required',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: healthColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$healthyCount of $totalHives Hives in good condition',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Mean AI Confidence: $avgConfidence%',
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
                const SizedBox(height: 16),

                // Queen Status Breakdown
                const Text(
                  'Colony Status Summary',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _statusMiniCard('Queen Present', '$presentCount', AppColors.queenPresentGreen, Icons.check_circle_outline),
                    const SizedBox(width: 8),
                    _statusMiniCard('Queen Absent', '$absentCount', AppColors.queenAbsentRed, Icons.error_outline),
                    const SizedBox(width: 8),
                    _statusMiniCard('Accepted', '$acceptedCount', AppColors.queenAcceptedBlue, Icons.verified_outlined),
                    const SizedBox(width: 8),
                    _statusMiniCard('Rejected', '$rejectedCount', AppColors.queenRejectedOrange, Icons.cancel_outlined),
                  ],
                ),
                const SizedBox(height: 16),

                // Environmental Averages
                const Text(
                  'Apiary Environmental Metrics',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _metricCard(
                        title: 'Avg Temperature',
                        value: '$avgTempStr°C',
                        icon: Icons.thermostat,
                        color: Colors.orange,
                        subtext: 'Optimal: 34°C - 36°C',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricCard(
                        title: 'Avg Humidity',
                        value: '$avgHumStr%',
                        icon: Icons.water_drop_outlined,
                        color: Colors.blue,
                        subtext: 'Optimal: 55% - 70%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Hive by Hive Breakdown List
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'All Monitored Hives',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                    Text(
                      '$totalHives Hives Total',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                    ),
                  ],
                ),
                if (hives.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(14)),
                    child: const Center(
                      child: Text(
                        'No hives added yet.\nConnected hives will display health metrics here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
                      ),
                    ),
                  )
                else
                  ...hives.map((h) => _hiveCard(context, h)),
                const SizedBox(height: 16),

                // AI Apiary-Wide Recommendations
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black, width: 1.4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.psychology_outlined, color: Colors.amber, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'AI Apiary Insights & Recommendations',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        totalHives == 0
                            ? 'ℹ️ No hives connected yet. Once you pair an IoT device or add a hive, real-time AI colony diagnostics and insights will appear here.'
                            : (absentCount > 0 || rejectedCount > 0
                                ? '⚠️ Attention Needed: $absentCount hive(s) detected with Queen Absent and $rejectedCount hive(s) with Queen Rejected. Prioritize physical inspections of affected boxes immediately to check for emergency queen cups or introduce new mated queens.'
                                : '✅ All $totalHives monitored colonies are exhibiting normal acoustic buzzing and brood thermoregulation. Continue standard routine apiary checks and maintain clean water sources nearby.'),
                        style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusMiniCard(String title, String count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              count,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
            ),
            const SizedBox(height: 4),
            Icon(icon, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtext,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _hiveCard(BuildContext context, HiveData hive) {
    final badgeColor = hive.labelColor;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => HiveDetailScreen(hive: hive, initialTab: 2),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10.0),
        padding: const EdgeInsets.all(14.0),
        decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            CircularGauge(
              percentage: hive.healthScore.toDouble(),
              size: 54,
              strokeWidth: 6,
              progressColor: badgeColor,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        hive.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: badgeColor, width: 1),
                        ),
                        child: Text(
                          hive.conditionLabel,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: badgeColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Temp: ${hive.temperature}',
                        style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Hum: ${hive.humidity}',
                        style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Audio: ${hive.acousticStatus}',
                        style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}
