import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../models/alert_model.dart';
import '../services/alert_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class AlertDetailsScreen extends StatelessWidget {
  final AlertModel alert;

  AlertDetailsScreen({super.key, required dynamic data})
      : alert = data is AlertModel
            ? data
            : (data is HiveData
                ? AlertModel(
                    id: data.id,
                    hiveId: data.name,
                    queenStatus: data.conditionLabel,
                    title: data.alertLabel,
                    message: data.alertMessage,
                    severity: data.alertSeverity,
                    timestamp: DateTime.now(),
                    recommendation: data.alertRecommendation,
                    detectedBy: data.detectedBy,
                  )
                : AlertModel(
                    id: 'unknown_alert',
                    hiveId: 'Unknown Hive',
                    queenStatus: 'Normal',
                    title: 'System Alert',
                    message: 'Alert details unavailable.',
                    severity: 'Low',
                    timestamp: DateTime.now(),
                    recommendation: 'Check hive sensors and telemetry.',
                  ));

  void _showResolveDialog(BuildContext context) {
    final notesController = TextEditingController(text: 'Field inspection completed. Anomaly resolved.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.black, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 24),
            SizedBox(width: 8),
            Text('Resolve Incident', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark "${alert.title}" for ${alert.hiveId} as resolved in the field and sync to cloud surveillance.',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            const Text(
              'Field Inspection Notes:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: notesController,
              maxLines: 2,
              style: const TextStyle(fontSize: 13, color: Colors.black),
              decoration: AppStyles.inputDecoration(
                hintText: 'e.g. Hive entrance cleared, queen verified',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.black, width: 1),
              ),
            ),
            onPressed: () async {
              final notes = notesController.text.trim();
              final resolver = UserProfileService().nickname;
              await AlertService().resolveAlert(
                alert,
                resolvedBy: resolver,
                notes: notes.isNotEmpty ? notes : 'Field inspection completed',
              );
              if (context.mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Incident resolved by $resolver and synced to cloud.'),
                    backgroundColor: const Color(0xFF2E7D32),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            child: const Text('Confirm Resolution', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _reopenIncident(BuildContext context) async {
    await AlertService().reopenAlert(alert);
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incident re-opened and moved to active alarms.'),
          backgroundColor: Colors.black87,
        ),
      );
    }
  }

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
                color: alert.isResolved ? const Color(0xFFE8F5E9) : alert.severityBgColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(
                    alert.isResolved ? Icons.check_circle : alert.iconData,
                    size: 36,
                    color: alert.isResolved ? const Color(0xFF2E7D32) : alert.severityColor,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              alert.hiveId,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                            ),
                            if (alert.isResolved) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E7D32),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'RESOLVED',
                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alert.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            decoration: alert.isResolved ? TextDecoration.lineThrough : null,
                          ),
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

            // Resolution info banner (if resolved)
            if (alert.isResolved) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E7D32), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified, color: Color(0xFF2E7D32), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Inspection Completed',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1B5E20)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Resolved by: ${alert.resolvedBy ?? 'Beekeeper'}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    if (alert.resolvedTimeFormatted != null)
                      Text(
                        'Time: ${alert.resolvedTimeFormatted}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    if (alert.resolutionNotes != null && alert.resolutionNotes!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Notes: "${alert.resolutionNotes}"',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black87),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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
            const SizedBox(height: 20),

            // Action Buttons
            if (!alert.isResolved)
              ElevatedButton.icon(
                onPressed: () => _showResolveDialog(context),
                icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                label: const Text(
                  'Resolve Alert / Mark Inspected',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Colors.black, width: 1.2),
                  ),
                ),
              )
            else if (UserProfileService().isAdminOrOwner)
              OutlinedButton.icon(
                onPressed: () => _reopenIncident(context),
                icon: const Icon(Icons.refresh, color: Colors.black87, size: 18),
                label: const Text(
                  'Re-open Incident (Move to Active)',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Colors.black54, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
