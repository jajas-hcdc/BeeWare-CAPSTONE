import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class EditHiveScreen extends StatefulWidget {
  final HiveData hive;

  const EditHiveScreen({super.key, required this.hive});

  @override
  State<EditHiveScreen> createState() => _EditHiveScreenState();
}

class _EditHiveScreenState extends State<EditHiveScreen> {
  late TextEditingController _nameController;
  late TextEditingController _notesController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.hive.name);
    _notesController = TextEditingController(text: widget.hive.notes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveHive() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a hive name'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final updatedHive = widget.hive.copyWith(
      name: name,
      notes: _notesController.text.trim(),
    );
    HiveService().updateHive(updatedHive);

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hive updated successfully!'),
          backgroundColor: Colors.black87,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  void _removeHive() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 1.5),
        ),
        title: const Text('Remove Hive?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove ${widget.hive.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.btnRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.black, width: 1),
              ),
            ),
            onPressed: () {
              HiveService().deleteHive(widget.hive.id);
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context, true); // Close screen
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: CustomHeaderBar(
        title: 'Edit Hive',
        showBack: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device ID info card (read-only hardware identity)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12, width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9C4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.developer_board_rounded, color: Colors.black, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hardware Node ID',
                          style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.hive.deviceId,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            const Text(
              'Hive Name',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w600),
              decoration: AppStyles.inputDecoration(hintText: 'Hive Name'),
            ),
            const SizedBox(height: 16),

            const Text(
              'Notes (Optional)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, color: Colors.black),
              decoration: AppStyles.inputDecoration(hintText: 'Notes on this hive colony'),
            ),
            const SizedBox(height: 24),

            // Save Button
            AppStyles.primaryButton(
              text: 'Save',
              isLoading: _isLoading,
              onPressed: _saveHive,
            ),
            const SizedBox(height: 12),

            // Remove Button
            AppStyles.primaryButton(
              text: 'Remove Hive',
              backgroundColor: AppColors.btnRed,
              textColor: Colors.black,
              onPressed: _removeHive,
            ),
          ],
        ),
      ),
    );
  }
}
