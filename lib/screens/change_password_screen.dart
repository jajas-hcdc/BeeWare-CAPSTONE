import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _retypePasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureRetype = true;
  bool _isLoading = false;
  String? _message;
  bool _isSuccess = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _retypePasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final currentP = _currentPasswordController.text;
    final newP = _newPasswordController.text;
    final retypeP = _retypePasswordController.text;

    if (currentP.isEmpty || newP.isEmpty || retypeP.isEmpty) {
      setState(() {
        _message = 'Please fill in all fields.';
        _isSuccess = false;
      });
      return;
    }

    if (newP != retypeP) {
      setState(() {
        _message = 'New passwords do not match.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await AuthService().updatePassword(newP);
      setState(() {
        _message = 'Password updated successfully!';
        _isSuccess = true;
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to update password: ${e.toString()}';
        _isSuccess = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: const CustomHeaderBar(
        title: 'Change Password',
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Current Password',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrent,
              style: const TextStyle(fontSize: 14, color: Colors.black),
              decoration: AppStyles.inputDecoration(
                hintText: 'Current password',
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.black87, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.black87,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'New Password',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _newPasswordController,
              obscureText: _obscureNew,
              style: const TextStyle(fontSize: 14, color: Colors.black),
              decoration: AppStyles.inputDecoration(
                hintText: 'New password',
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.black87, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.black87,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Retype new Password',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _retypePasswordController,
              obscureText: _obscureRetype,
              style: const TextStyle(fontSize: 14, color: Colors.black),
              decoration: AppStyles.inputDecoration(
                hintText: 'Retype new password',
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.black87, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureRetype ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.black87,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureRetype = !_obscureRetype),
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_message != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isSuccess ? Colors.green.shade100 : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isSuccess ? Colors.green.shade400 : Colors.red.shade400,
                  ),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _isSuccess ? Colors.green.shade900 : Colors.red.shade900,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 14),
            ],

            AppStyles.primaryButton(
              text: 'Save',
              isLoading: _isLoading,
              onPressed: _updatePassword,
            ),
          ],
        ),
      ),
    );
  }
}
