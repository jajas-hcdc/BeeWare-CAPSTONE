import 'dart:io';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import 'change_password_screen.dart';
import 'notification_settings_screen.dart';
import 'about_screen.dart';
import 'logout_screen.dart';
import 'user_profile_screen.dart';
import 'user_guide_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'English';

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final email = user?.email ?? 'Thebeekeeper@example.com';

    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          color: Colors.white,
          child: const SafeArea(
            bottom: false,
            child: Center(
              child: Text(
                'Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile header card with live avatar & nickname sync
            AnimatedBuilder(
              animation: UserProfileService(),
              builder: (context, child) {
                final nick = UserProfileService().nickname.trim();
                final displayName = nick.isNotEmpty ? nick : (user?.displayName ?? 'The Beekeeper');
                final avatar = UserProfileService().selectedAvatar;
                final customPath = UserProfileService().customImagePath;

                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const UserProfileScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
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
                            child: _buildProfileAvatar(avatar, customPath),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.black45, size: 22),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // Settings Options List
            // 1. Change password (moved from Management to top of Notification Settings)
            _settingsTile(
              context: context,
              icon: Icons.lock_outline,
              title: 'Change password',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
                );
              },
            ),
            const SizedBox(height: 10),

            // 2. Notification Settings
            _settingsTile(
              context: context,
              icon: Icons.notifications_none,
              title: 'Notification Settings',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const NotificationSettingsScreen()),
                );
              },
            ),
            const SizedBox(height: 10),

            // 3. App User Guide & Tutorials
            _settingsTile(
              context: context,
              icon: Icons.menu_book_outlined,
              title: 'App User Guide & Tutorials',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const UserGuideScreen()),
                );
              },
            ),
            const SizedBox(height: 10),

            // 4. Language (placed above About BeeWare)
            _settingsTile(
              context: context,
              icon: Icons.language,
              title: 'Language',
              trailingText: _selectedLanguage,
              onTap: () => _showLanguageBottomSheet(context),
            ),
            const SizedBox(height: 10),

            // 5. About BeeWare
            _settingsTile(
              context: context,
              icon: Icons.info_outline,
              title: 'About BeeWare',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AboutBeeWareScreen()),
                );
              },
            ),
            const SizedBox(height: 20),

            // Log out button
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const LogoutScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: Row(
                  children: const [
                    Icon(Icons.logout, color: Colors.red, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Log out',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(String key, String? customPath) {
    if (key == 'custom' && customPath != null && File(customPath).existsSync()) {
      return ClipOval(
        child: Image.file(
          File(customPath),
          width: 54,
          height: 54,
          fit: BoxFit.cover,
        ),
      );
    }
    switch (key) {
      case 'mascot':
        return ClipOval(
          child: Image.asset(
            'assets/images/bee_mascot_large.png',
            width: 44,
            height: 44,
            fit: BoxFit.contain,
          ),
        );
      case 'bee':
        return ClipOval(
          child: Image.asset(
            'assets/images/bee_icon.png',
            width: 40,
            height: 40,
            fit: BoxFit.contain,
          ),
        );
      case 'farmer':
        return const Icon(Icons.agriculture_rounded, size: 34, color: Colors.black);
      case 'male':
        return const Icon(Icons.face_rounded, size: 36, color: Colors.black);
      case 'female':
        return const Icon(Icons.face_3_rounded, size: 36, color: Colors.black);
      default:
        return const Icon(Icons.person_outline, size: 34, color: Colors.black);
    }
  }

  void _showLanguageBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final languages = ['English'];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Language',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 14),
                ...languages.map((lang) {
                  final isSelected = lang == _selectedLanguage;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      lang,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.black)
                        : const Icon(Icons.circle_outlined, color: Colors.black26),
                    onTap: () {
                      setState(() {
                        _selectedLanguage = lang;
                      });
                      Navigator.of(ctx).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _settingsTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: Colors.black, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right, color: Colors.black, size: 22),
          ],
        ),
      ),
    );
  }
}
