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
import 'services/user_profile_service.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'screens/login_screen.dart';
import 'screens/offline_screen.dart';
import 'theme/app_theme.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseService.initialize();
  debugPrint('FCM background message received: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseService.initialize();
  await FirebaseService().initializeFCM();
  await UserProfileService().initialize();
  runApp(const BeeWareApp());
}

class BeeWareApp extends StatelessWidget {
  const BeeWareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    return AnimatedBuilder(
      animation: ConnectivityService(),
      builder: (context, _) {
        if (!ConnectivityService().isOnline) {
          return const OfflineScreen();
        }

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
              return const LoginScreen();
            }

            return const MainNavigation();
          },
        );
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
  StreamSubscription? _msgSub;
  StreamSubscription? _msgOpenedSub;

  @override
  void initState() {
    super.initState();
    // 1. Foreground in-app notification banner
    _msgSub = FirebaseService().onMessageStream.listen((message) {
      if (!mounted) return;
      final notification = message.notification;
      final data = message.data;
      final hiveId = data['hiveId'] as String?;
      final queenStatus = data['queenStatus'] as String?;

      final title = notification?.title ?? (queenStatus != null ? '⚠️ $queenStatus Detected!' : 'Hive Alert');
      final body = notification?.body ?? 'New sensor telemetry event recorded.';

      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          backgroundColor: const Color(0xFFFFF8E1),
          leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 28),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(fontSize: 11, color: Colors.black87)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('Dismiss', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFCC00),
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                _navigateToHive(hiveId);
              },
              child: const Text('Inspect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );
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
  void dispose() {
    _msgSub?.cancel();
    _msgOpenedSub?.cancel();
    super.dispose();
  }

  void _navigateToHive(String? hiveId) {
    final hives = HiveService().hives;
    HiveData? target;
    if (hiveId != null && hiveId.isNotEmpty) {
      target = hives.firstWhere(
        (h) => h.id == hiveId || h.deviceId == hiveId || h.name.toLowerCase() == hiveId.toLowerCase(),
        orElse: () => hives.isNotEmpty ? hives.first : HiveData.samples.first,
      );
    } else {
      target = hives.isNotEmpty ? hives.first : HiveData.samples.first;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HiveDetailScreen(hive: target!, initialTab: 2),
      ),
    );
  }

  void _onTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(onOpenAlerts: () => setState(() => _selectedIndex = 2)),
      const HivesScreen(),
      const AlertsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
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
                  badgeStream: FirebaseService().alertCountStream(),
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
    Stream<int>? badgeStream,
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
                if (badgeStream != null)
                  StreamBuilder<int>(
                    stream: badgeStream,
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      if (count <= 0) return const SizedBox.shrink();
                      return Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                          child: Text(
                            '$count',
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
