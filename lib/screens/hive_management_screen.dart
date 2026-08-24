import 'package:flutter/material.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/beehive_icon.dart';
import 'edit_hive_screen.dart';

class HiveManagementScreen extends StatelessWidget {
  const HiveManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HiveService(),
      builder: (context, child) {
        final hives = HiveService().hives;

        return Scaffold(
          backgroundColor: AppColors.screenYellow,
          appBar: CustomHeaderBar(
            title: 'Hive management',
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
          body: hives.isEmpty
              ? const Center(
                  child: Text(
                    'No hives to manage.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  itemCount: hives.length,
                  itemBuilder: (context, index) {
                    final hive = hives[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => EditHiveScreen(hive: hive),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                          decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            children: [
                              const BeehiveIcon(size: 38),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      hive.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Device ID: ${hive.deviceId}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.black, size: 24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
