import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AlertModel {
  final String id;
  final String hiveId;
  final String queenStatus;
  final String title;
  final String message;
  final String severity; // 'Critical', 'Warning', 'Info'
  final DateTime timestamp;
  final String recommendation;
  final String detectedBy;
  final String? userId;
  final Map<String, dynamic>? additionalData;

  const AlertModel({
    required this.id,
    required this.hiveId,
    required this.queenStatus,
    required this.title,
    required this.message,
    required this.severity,
    required this.timestamp,
    required this.recommendation,
    this.detectedBy = 'AI Acoustic & Sensor Model',
    this.userId,
    this.additionalData,
  });

  static String deduceSeverity(String queenStatus) {
    final status = queenStatus.toLowerCase();
    if (status.contains('absent') || status.contains('queenless')) {
      return 'Critical';
    }
    if (status.contains('rejected') || status.contains('stress') || status.contains('swarming')) {
      return 'Warning';
    }
    return 'Info';
  }

  static String deduceRecommendation(String queenStatus) {
    final status = queenStatus.toLowerCase();
    if (status.contains('absent') || status.contains('queenless')) {
      return 'Inspect frames for emergency queen cells or introduce a new mated queen promptly.';
    }
    if (status.contains('rejected')) {
      return 'Check the queen cage immediately and examine worker aggression.';
    }
    if (status.contains('accepted')) {
      return 'Queen successfully accepted. Avoid disturbing brood box for 5 days.';
    }
    return 'Colony is queenright and stable. Continue regular inspection routine.';
  }

  factory AlertModel.fromMap(Map<String, dynamic> data, [String? id]) {
    final rawStatus = data['queenStatus'] ?? data['queen_status'] ?? 'Queen Present';
    final rawSeverity = data['severity'] ?? data['alertSeverity'] ?? deduceSeverity(rawStatus);

    DateTime parsedDate;
    if (data['timestamp'] != null) {
      if (data['timestamp'] is DateTime) {
        parsedDate = data['timestamp'] as DateTime;
      } else if (data['timestamp'] is String) {
        parsedDate = DateTime.tryParse(data['timestamp'] as String) ?? DateTime.now();
      } else {
        try {
          // Cloud Firestore Timestamp object
          parsedDate = (data['timestamp'] as dynamic).toDate();
        } catch (_) {
          parsedDate = DateTime.now();
        }
      }
    } else {
      parsedDate = DateTime.now();
    }

    return AlertModel(
      id: id ?? data['id'] ?? 'alert_${DateTime.now().millisecondsSinceEpoch}',
      hiveId: data['hiveId'] ?? data['hive_id'] ?? 'Hive 1',
      queenStatus: rawStatus,
      title: data['title'] ?? '$rawStatus Alert',
      message: data['message'] ?? 'Colony state: $rawStatus',
      severity: rawSeverity,
      timestamp: parsedDate,
      recommendation: data['recommendation'] ?? data['alertRecommendation'] ?? deduceRecommendation(rawStatus),
      detectedBy: data['detectedBy'] ?? 'AI Multi-Sensor Acoustic Model',
      userId: data['userId'],
      additionalData: data['additional_data'] ?? data['payload'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hiveId': hiveId,
      'queenStatus': queenStatus,
      'title': title,
      'message': message,
      'severity': severity,
      'timestamp': timestamp.toIso8601String(),
      'recommendation': recommendation,
      'detectedBy': detectedBy,
      if (userId != null) 'userId': userId,
      if (additionalData != null) 'payload': additionalData,
    };
  }

  Color get severityColor {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return const Color(0xFFFFB300);
      case 'info':
      default:
        return AppColors.healthyGreen;
    }
  }

  Color get severityBgColor {
    switch (severity.toLowerCase()) {
      case 'critical':
        return AppColors.swarmingRedBg;
      case 'warning':
        return AppColors.stressYellowBg;
      case 'info':
      default:
        return AppColors.healthyGreenBg;
    }
  }

  IconData get iconData {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'info':
      default:
        return Icons.check_circle_outline;
    }
  }

  String get timeFormatted {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}
