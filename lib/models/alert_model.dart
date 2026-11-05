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
  final bool isResolved;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolvedTimeFormatted;
  final String? resolutionNotes;

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
    this.isResolved = false,
    this.resolvedAt,
    this.resolvedBy,
    this.resolvedTimeFormatted,
    this.resolutionNotes,
  });

  AlertModel copyWith({
    String? id,
    String? hiveId,
    String? queenStatus,
    String? title,
    String? message,
    String? severity,
    DateTime? timestamp,
    String? recommendation,
    String? detectedBy,
    String? userId,
    Map<String, dynamic>? additionalData,
    bool? isResolved,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? resolvedTimeFormatted,
    String? resolutionNotes,
  }) {
    return AlertModel(
      id: id ?? this.id,
      hiveId: hiveId ?? this.hiveId,
      queenStatus: queenStatus ?? this.queenStatus,
      title: title ?? this.title,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      timestamp: timestamp ?? this.timestamp,
      recommendation: recommendation ?? this.recommendation,
      detectedBy: detectedBy ?? this.detectedBy,
      userId: userId ?? this.userId,
      additionalData: additionalData ?? this.additionalData,
      isResolved: isResolved ?? this.isResolved,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      resolvedTimeFormatted: resolvedTimeFormatted ?? this.resolvedTimeFormatted,
      resolutionNotes: resolutionNotes ?? this.resolutionNotes,
    );
  }

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

    final bool isResolved = data['resolved'] == true ||
        data['status'] == 'resolved' ||
        (data['isResolved'] == true);

    DateTime? resolvedAt;
    if (data['resolvedAt'] != null) {
      if (data['resolvedAt'] is int) {
        resolvedAt = DateTime.fromMillisecondsSinceEpoch(data['resolvedAt'] as int);
      } else if (data['resolvedAt'] is DateTime) {
        resolvedAt = data['resolvedAt'] as DateTime;
      } else if (data['resolvedAt'] is String) {
        resolvedAt = DateTime.tryParse(data['resolvedAt'] as String);
      } else {
        try {
          resolvedAt = (data['resolvedAt'] as dynamic).toDate();
        } catch (_) {}
      }
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
      isResolved: isResolved,
      resolvedAt: resolvedAt,
      resolvedBy: data['resolvedBy'] as String?,
      resolvedTimeFormatted: data['resolvedTimeFormatted'] as String?,
      resolutionNotes: (data['resolutionNotes'] ?? data['notes']) as String?,
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
      'resolved': isResolved,
      'status': isResolved ? 'resolved' : 'active',
      if (resolvedAt != null) 'resolvedAt': resolvedAt!.millisecondsSinceEpoch,
      if (resolvedBy != null) 'resolvedBy': resolvedBy,
      if (resolvedTimeFormatted != null) 'resolvedTimeFormatted': resolvedTimeFormatted,
      if (resolutionNotes != null) 'resolutionNotes': resolutionNotes,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        ...toMap(),
      };

  factory AlertModel.fromJson(Map<String, dynamic> json) =>
      AlertModel.fromMap(json, json['id']);

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
