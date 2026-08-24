import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/calendar_picker_dialog.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late String _selectedGender;
  late DateTime _selectedDob;
  final List<String> _genders = ['MALE', 'FEMALE', 'OTHERS'];
  late String _selectedAvatar;
  String? _customImagePath;
  late String _nickname;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final profile = UserProfileService();
    _nickname = profile.nickname;
    _selectedAvatar = profile.selectedAvatar;
    _customImagePath = profile.customImagePath;
    _selectedGender = profile.selectedGender;
    _selectedDob = profile.selectedDob;
  }

  void _showEditNicknameDialog() {
    final controller = TextEditingController(text: _nickname);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Nickname', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter your nickname',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFCC00),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                final newNick = controller.text.trim();
                setState(() => _nickname = newNick);
                UserProfileService().setNickname(newNick);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (photo != null) {
        final path = photo.path;
        setState(() {
          _selectedAvatar = 'custom';
          _customImagePath = path;
        });
        UserProfileService().setCustomImage(path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Custom profile photo updated successfully!')),
          );
        }
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load image: $e')),
        );
      }
    }
  }

  String _formatDob(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$month/$day/${d.year}';
  }

  Widget _buildAvatarWidget() {
    if (_selectedAvatar == 'custom' && _customImagePath != null && File(_customImagePath!).existsSync()) {
      return ClipOval(
        child: Image.file(
          File(_customImagePath!),
          width: 60,
          height: 60,
          fit: BoxFit.cover,
        ),
      );
    }
    switch (_selectedAvatar) {
      case 'mascot':
        return ClipOval(
          child: Image.asset(
            'assets/images/bee_mascot_large.png',
            width: 50,
            height: 50,
            fit: BoxFit.contain,
          ),
        );
      case 'bee':
        return ClipOval(
          child: Image.asset(
            'assets/images/bee_icon.png',
            width: 46,
            height: 46,
            fit: BoxFit.contain,
          ),
        );
      case 'farmer':
        return const Icon(Icons.agriculture_rounded, size: 36, color: Colors.black);
      case 'male':
        return const Icon(Icons.face_rounded, size: 38, color: Colors.black);
      case 'female':
        return const Icon(Icons.face_3_rounded, size: 38, color: Colors.black);
      default:
        return const Icon(Icons.person_outline, size: 38, color: Colors.black);
    }
  }

  void _showChangePhotoModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Choose Profile Photo',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select an Apiary Avatar:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _avatarOption('default', const Icon(Icons.person_outline, size: 28)),
                    _avatarOption('male', const Icon(Icons.face_rounded, size: 28)),
                    _avatarOption('female', const Icon(Icons.face_3_rounded, size: 28)),
                    _avatarOption(
                      'mascot',
                      Image.asset('assets/images/bee_mascot_large.png', width: 32, height: 32, fit: BoxFit.contain),
                    ),
                    _avatarOption(
                      'bee',
                      Image.asset('assets/images/bee_icon.png', width: 30, height: 30, fit: BoxFit.contain),
                    ),
                    _avatarOption('farmer', const Icon(Icons.agriculture_rounded, size: 28)),
                  ],
                ),
                const Divider(height: 28, color: Colors.black12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.black, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.camera_alt_outlined, color: Colors.black, size: 20),
                        label: const Text('Camera', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _pickImage(ImageSource.camera);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.black, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.photo_library_outlined, color: Colors.black, size: 20),
                        label: const Text('Gallery', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _pickImage(ImageSource.gallery);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _avatarOption(String key, Widget iconWidget) {
    final isSelected = _selectedAvatar == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAvatar = key;
          _customImagePath = null;
        });
        UserProfileService().setAvatar(key);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated successfully!')),
        );
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFCC00) : const Color(0xFFF5F5F5),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.black : Colors.black26,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(child: iconWidget),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final displayName = user?.displayName ?? 'justinepugosa';
    final email = user?.email ?? 'justinepugosa@gmail.com';

    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: const CustomHeaderBar(
        title: 'User Profile',
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Profile Card
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _showChangePhotoModal,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                          child: Center(child: _buildAvatarWidget()),
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _showChangePhotoModal,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.black87, width: 1),
                          ),
                          child: const Text(
                            'Change Photo',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
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
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Username, Nickname & Email detail card
            Container(
              decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Text(
                      'Username: $displayName',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                  ),
                  const Divider(color: Colors.black12, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Nickname: $_nickname',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                        ),
                        GestureDetector(
                          onTap: _showEditNicknameDialog,
                          child: const Icon(Icons.edit_outlined, size: 16, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.black12, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Text(
                      'Email: $email',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Gender Field
            const Text(
              'Gender',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1.2),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGender,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black),
                  items: _genders.map((g) {
                    return DropdownMenuItem(
                      value: g,
                      child: Text(g),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedGender = val);
                      UserProfileService().setGender(val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date of Birth Field
            const Text(
              'Date of Birth',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => CustomCalendarPickerDialog(
                    initialDate: _selectedDob,
                    onDateSelected: (date) {
                      setState(() => _selectedDob = date);
                      UserProfileService().setDob(date);
                    },
                  ),
                );
              },
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 1.2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDob(_selectedDob),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black),
                    ),
                    const Icon(Icons.calendar_today_outlined, size: 20, color: Colors.black87),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
