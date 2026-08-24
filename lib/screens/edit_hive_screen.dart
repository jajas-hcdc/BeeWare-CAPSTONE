import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class EditHiveScreen extends StatefulWidget {
  final HiveData? hive; // If null, Add mode; if provided, Edit mode

  const EditHiveScreen({super.key, this.hive});

  @override
  State<EditHiveScreen> createState() => _EditHiveScreenState();
}

class _EditHiveScreenState extends State<EditHiveScreen> {
  late TextEditingController _nameController;
  late TextEditingController _deviceIdController;
  late TextEditingController _notesController;
  bool _isLoading = false;

  bool get isEdit => widget.hive != null;

  @override
  void initState() {
    super.initState();
    final hiveCount = HiveService().hives.length;
    _nameController = TextEditingController(text: widget.hive?.name ?? 'Hive ${hiveCount + 1}');
    _deviceIdController = TextEditingController(text: widget.hive?.deviceId ?? '');
    _notesController = TextEditingController(text: widget.hive?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _deviceIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _saveHive() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);

    if (isEdit) {
      final updatedHive = widget.hive!.copyWith(
        name: name,
        deviceId: _deviceIdController.text.trim(),
        notes: _notesController.text.trim(),
      );
      HiveService().updateHive(updatedHive);
    } else {
      final hiveCount = HiveService().hives.length;
      final newHive = HiveData(
        id: 'hive_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        deviceId: _deviceIdController.text.trim().isEmpty
            ? 'BW-00${hiveCount + 1}-DEV'
            : _deviceIdController.text.trim(),
        notes: _notesController.text.trim(),
        conditionLabel: 'Healthy Colony',
        confidence: 90,
        healthScore: 90,
        temperature: '33.5',
        humidity: '65',
        acoustic: 'Normal Activity',
        updated: 'Just now',
        isAlert: false,
        alertLabel: 'Healthy Colony',
        alertMessage: 'Colony is stable.',
      );
      HiveService().addHive(newHive);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isEdit ? 'Hive updated successfully!' : 'Hive added successfully!'),
        backgroundColor: Colors.black87,
      ),
    );

    Navigator.pop(context, true);
  }

  void _removeHive() {
    if (!isEdit) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 1.5),
        ),
        title: const Text('Remove Hive?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove ${widget.hive!.name}?'),
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
              HiveService().deleteHive(widget.hive!.id);
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
        title: isEdit ? widget.hive!.name : 'Add Hive',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black, size: 28),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const EditHiveScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Hive Name',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w600),
              decoration: AppStyles.inputDecoration(hintText: 'Hive 1'),
            ),
            const SizedBox(height: 16),

            const Text(
              'Device ID',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _deviceIdController,
              style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w600),
              decoration: AppStyles.inputDecoration(hintText: '(Device ID)'),
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
              decoration: AppStyles.inputDecoration(hintText: 'Notes on this'),
            ),
            const SizedBox(height: 24),

            // Save Button
            AppStyles.primaryButton(
              text: 'Save',
              isLoading: _isLoading,
              onPressed: _saveHive,
            ),
            const SizedBox(height: 12),

            // Remove Button (only in edit mode)
            if (isEdit)
              AppStyles.primaryButton(
                text: 'Remove',
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
