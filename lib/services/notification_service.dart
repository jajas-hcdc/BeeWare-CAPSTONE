import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/alerts_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static const String channelId = 'beeware_urgent_alerts';
  static const String channelName = 'BeeWare Urgent Alerts';
  static const String channelDescription =
      'High-priority alerts and buzz notifications for your bee hives';

  bool get _isTesting => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> initialize() async {
    if (_isInitialized) return;

    if (_isTesting) {
      _isInitialized = true;
      return;
    }

    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('📱 [BeeWare] System notification tapped with payload: ${response.payload}');
          _handleNotificationTap(response.payload);
        },
      );

      // Create Android Notification Channel with Maximum Importance for Pop-up / Heads-Up Banners
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );

        await androidImplementation.createNotificationChannel(channel);

        // Request runtime permission on Android 13+ (POST_NOTIFICATIONS)
        final granted = await androidImplementation.requestNotificationsPermission();
        debugPrint('📱 [BeeWare] Android notification permission granted: $granted');
      }

      _isInitialized = true;
      debugPrint('✅ [BeeWare] NotificationService initialized successfully');
    } catch (e) {
      debugPrint('❌ [BeeWare] Error initializing NotificationService: $e');
    }
  }

  void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      try {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AlertsScreen()),
        );
      } catch (e) {
        debugPrint('Navigation on notification tap failed: $e');
      }
    }
  }

  /// Displays a native system pop-up notification (Heads-Up Banner on phone)
  Future<void> showNotification({
    int? id,
    required String title,
    required String body,
    String? payload,
    String? severity,
  }) async {
    if (_isTesting) {
      _showInAppTopBanner(title, body, severity: severity);
      return;
    }

    if (!_isInitialized) {
      await initialize();
    }

    final notifId = id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'BeeWare Notification',
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'BeeWare Smart Apiary',
      ),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notificationsPlugin.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
      debugPrint('🔔 [BeeWare] Pop-up notification posted: "$title" - "$body"');
    } catch (e) {
      debugPrint('❌ [BeeWare] Failed to show system notification: $e');
    }

    // Also trigger in-app heads-up overlay banner if user is currently inside the app
    _showInAppTopBanner(title, body, severity: severity);
  }

  /// Displays a notification when an IoT audio recording occurs (disabled to prevent intrusive prompts on app launch)
  Future<void> showAudioRecordedNotification({
    required String deviceId,
    required String recordedTime,
    required String trigger,
    int? frequency,
  }) async {
    // Disabled: Routine audio captures are saved silently in audio history
    // and should not prompt intrusive notifications or banners.
    return;
  }

  /// In-app floating drop-down banner for immediate visibility when inside the app
  void _showInAppTopBanner(String title, String body, {String? severity}) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    try {
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) return;

      Color accentColor = const Color(0xFFFFCC00);
      IconData icon = Icons.notifications_active;

      final sev = severity?.toLowerCase() ?? '';
      if (sev == 'critical') {
        accentColor = const Color(0xFFD32F2F);
        icon = Icons.warning_rounded;
      } else if (sev == 'warning') {
        accentColor = const Color(0xFFFF9800);
        icon = Icons.error_outline_rounded;
      } else if (title.contains('🎤') || title.contains('Audio')) {
        accentColor = const Color(0xFF1976D2);
        icon = Icons.mic_rounded;
      }

      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => _TopBannerWidget(
          title: title,
          body: body,
          accentColor: accentColor,
          icon: icon,
          onDismiss: () {
            entry.remove();
          },
        ),
      );

      overlay.insert(entry);

      // Auto-dismiss after 4.5 seconds
      Future.delayed(const Duration(milliseconds: 4500), () {
        if (entry.mounted) {
          entry.remove();
        }
      });
    } catch (e) {
      debugPrint('In-app banner display error: $e');
    }
  }
}

class _TopBannerWidget extends StatefulWidget {
  final String title;
  final String body;
  final Color accentColor;
  final IconData icon;
  final VoidCallback onDismiss;

  const _TopBannerWidget({
    required this.title,
    required this.body,
    required this.accentColor,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _animController.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _dismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.accentColor.withValues(alpha: 0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: widget.accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.body,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _dismiss,
                    child: const Icon(Icons.close, size: 18, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
