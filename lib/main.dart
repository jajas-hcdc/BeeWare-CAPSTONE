import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'models/hive_data.dart';
import 'screens/home_screen.dart';
import 'screens/hives_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/hive_detail_screen.dart';
import 'services/firebase_service.dart';
import 'services/hive_service.dart';
import 'services/alert_service.dart';
import 'services/notification_service.dart';
import 'services/user_profile_service.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'services/backend_service.dart';
import 'services/model_service.dart';
import 'screens/login_screen.dart';
import 'screens/offline_screen.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseService.initialize();
  debugPrint('FCM background message received: ${message.messageId}');
  if (message.notification == null && message.data.isNotEmpty) {
    await NotificationService().initialize();
    final title = message.data['title'] ?? '🐝 BeeWare Alert';
    final body = message.data['message'] ?? 'Anomaly detected in hive telemetry.';
    await NotificationService().showNotification(
      title: title,
      body: body,
      payload: message.data['hiveId'] ?? message.data['deviceId'],
      severity: message.data['severity'],
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService().initialize();
  FirebaseService().initializeFCM();
  await UserProfileService().initialize();
  try {
    await ModelService().initialize();
  } catch (e) {
    debugPrint('ℹ️ TFLite model pre-load skipped: $e');
  }

  // Wake up Render backend if sleeping on free tier
  BackendService().wakeUpBackend();

  // Listen to foreground FCM messages dispatched by Render backend
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('📱 [BeeWare] Foreground FCM message received from Render: ${message.messageId}');
    if (!AlertService().pushEnabled || !AlertService().alertsEnabled) return;
    final title = message.notification?.title ?? message.data['title'] ?? '🐝 BeeWare Alert';
    final body = message.notification?.body ?? message.data['message'] ?? 'Anomaly detected in hive telemetry.';
    String? targetDevice = (message.data['deviceId'] ?? message.data['hiveId'])?.toString();
    if (targetDevice == null || targetDevice.isEmpty) {
      final match = RegExp(r'BW-[A-Za-z0-9-]+').firstMatch('$title $body');
      targetDevice = match?.group(0);
    }
    // Ignore FCM push notifications when the ESP32 device is unplugged or offline
    if (targetDevice == null || !HiveService().isDeviceActivelyOnline(targetDevice)) {
      debugPrint('🔕 [BeeWare] Ignored FCM notification for unplugged/offline device: $targetDevice');
      return;
    }
    NotificationService().showNotification(
      title: title,
      body: body,
      payload: targetDevice,
      severity: message.data['severity'],
    );
  });

  runApp(const BeeWareApp());
}

class BeeWareApp extends StatelessWidget {
  const BeeWareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'BeeWare',
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: AppColors.primaryYellow,
        scaffoldBackgroundColor: AppColors.screenYellow,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: AppColors.primaryYellow,
          secondary: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
          iconTheme: IconThemeData(color: Colors.black),
        ),
        fontFamily: 'Roboto',
      ),
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
      routes: {
        HiveDetailScreen.routeName: (context) => const HiveDetailScreen(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.screenYellow,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
              ),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null || user.isAnonymous) {
          return AnimatedBuilder(
            animation: ConnectivityService(),
            builder: (context, _) {
              if (!ConnectivityService().isOnline) {
                return const OfflineScreen();
              }
              return const LoginScreen();
            },
          );
        }

        // Logged in user: display MainNavigation with cached data and dynamic offline banners
        return const MainNavigation();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  late final PageController _pageController;
  StreamSubscription? _msgOpenedSub;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);

    // Start HTTP polling for live ESP32 SQLite telemetry (30s interval to conserve data & battery)
    BackendService().startTelemetryPolling(interval: const Duration(seconds: 30));

    // Clear any stale MaterialBanner
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
      }
    });

    // 2. Tapped notification from background state
    _msgOpenedSub = FirebaseService().onMessageOpenedAppStream.listen((message) {
      if (mounted) {
        final hiveId = message.data['hiveId'] as String?;
        _navigateToHive(hiveId);
      }
    });

    // 3. Tapped notification from terminated state
    try {
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null && mounted) {
          final hiveId = message.data['hiveId'] as String?;
          _navigateToHive(hiveId);
        }
      });
    } catch (_) {}
  }

  @override
  void reassemble() {
    super.reassemble();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
      }
    });
  }

  @override
  void dispose() {
    BackendService().stopTelemetryPolling();
    _pageController.dispose();
    _msgOpenedSub?.cancel();
    super.dispose();
  }

  void _navigateToHive(String? hiveId) {
    final hives = HiveService().hives;
    if (hives.isEmpty) {
      _onTap(1);
      return;
    }

    HiveData target = hives.first;
    if (hiveId != null && hiveId.isNotEmpty) {
      try {
        target = hives.firstWhere(
          (h) => h.id == hiveId || h.deviceId == hiveId || h.name.toLowerCase() == hiveId.toLowerCase(),
        );
      } catch (_) {
        target = hives.first;
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HiveDetailScreen(hive: target, initialTab: 2),
      ),
    );
  }

  void _onTap(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(onOpenAlerts: () => _onTap(2)),
      const HivesScreen(),
      const AlertsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.black12, width: 1.0),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  label: 'Home',
                  icon: Icons.emoji_nature,
                  selectedIcon: Icons.emoji_nature,
                ),
                _buildNavItem(
                  index: 1,
                  label: 'Hives',
                  icon: Icons.inventory_2_outlined,
                  selectedIcon: Icons.inventory_2,
                ),
                _buildNavItem(
                  index: 2,
                  label: 'Alerts',
                  icon: Icons.notifications_none,
                  selectedIcon: Icons.notifications,
                  hasAlertBadge: true,
                ),
                _buildNavItem(
                  index: 3,
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    bool hasAlertBadge = false,
  }) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? const Color(0xFFF5A623) : Colors.black87;

    return Expanded(
      child: InkWell(
        onTap: () => _onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: color,
                  size: 24,
                ),
                if (hasAlertBadge)
                  AnimatedBuilder(
                    animation: AlertService(),
                    builder: (context, child) {
                      final count = AlertService().alerts.length;
                      if (count <= 0) return const SizedBox.shrink();
                      return Positioned(
                        right: -6,
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
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
