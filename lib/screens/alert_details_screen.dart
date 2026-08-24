import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../models/alert_model.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class AlertDetailsScreen extends StatelessWidget {
  final AlertModel alert;

  AlertDetailsScreen({super.key, required dynamic data})
      : alert = data is AlertModel
            ? data
            : AlertModel(
                id: (data as HiveData).id,
                hiveId: data.name,
                queenStatus: data.conditionLabel,
                title: data.alertLabel,
                message: data.alertMessage,
                severity: data.alertSeverity,
                timestamp: DateTime.now(),
                recommendation: data.alertRecommendation,
                detectedBy: data.detectedBy,
              );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: const CustomHeaderBar(
        title: 'Alerts Details',
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Alert Card Header
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: AppStyles.cardDecoration(
                color: alert.severityBgColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(alert.iconData, size: 36, color: alert.severityColor),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.hiveId,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alert.title,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    alert.timeFormatted,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Detailed specification table
            Container(
              decoration: AppStyles.cardDecoration(
                color: const Color(0xFFF2FAF4),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _specRow('Queen Status', alert.queenStatus, isFirst: true),
                  const Divider(color: Colors.black12, height: 1),
                  _specRow('Time', alert.timeFormatted),
                  const Divider(color: Colors.black12, height: 1),
                  _specRow('Severity', alert.severity == 'Critical' ? 'High' : (alert.severity == 'Warning' ? 'Medium' : 'Low')),
                  const Divider(color: Colors.black12, height: 1),
                  _specRow('Detected by', alert.detectedBy),
                  const Divider(color: Colors.black12, height: 1),
                  _specRow('Description', alert.message),
                  const Divider(color: Colors.black12, height: 1),
                  _specRow('Recommendation', alert.recommendation, isLast: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _specRow(String label, String value, {bool isFirst = false, bool isLast = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
