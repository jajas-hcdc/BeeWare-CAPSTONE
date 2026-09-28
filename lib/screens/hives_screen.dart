import 'package:flutter/material.dart';
import '../models/hive_data.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/beehive_icon.dart';
import 'hive_detail_screen.dart';
import 'hive_management_screen.dart';
import 'qr_hive_scanner_screen.dart';

class HivesScreen extends StatefulWidget {
  const HivesScreen({super.key});

  @override
  State<HivesScreen> createState() => _HivesScreenState();
}

class _HivesScreenState extends State<HivesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  void _showAddHiveOptions() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrHiveScannerScreen()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: HiveService(),
      builder: (context, child) {
        final allHives = HiveService().hives;
        final filteredHives = allHives.where((h) {
          final clean = h.acoustic.trim().toLowerCase();
          final isNoBuzz = clean == '0' ||
              clean == '0 hz' ||
              clean.startsWith('0 ') ||
              h.acousticStatus.toLowerCase().contains('not detected');
          final displayCondition = isNoBuzz ? 'No Buzz Detected' : h.conditionLabel;
          return h.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              h.conditionLabel.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              displayCondition.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        return Scaffold(
          backgroundColor: AppColors.screenYellow,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              color: Colors.white,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'My Hives',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add, color: Colors.black, size: 28),
                            onPressed: _showAddHiveOptions,
                          ),
                          IconButton(
                            icon: const Icon(Icons.menu, color: Colors.black, size: 26),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const HiveManagementScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 8.0),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 1.2),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.black87, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: const TextStyle(fontSize: 13, color: Colors.black),
                          decoration: const InputDecoration(
                            hintText: 'Search hive..',
                            hintStyle: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(Icons.clear, color: Colors.black54, size: 18),
                        ),
                    ],
                  ),
                ),
              ),

              // Content: Empty State vs List
              Expanded(
                child: filteredHives.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        itemCount: filteredHives.length,
                        itemBuilder: (context, index) {
                          final hive = filteredHives[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: _buildHiveCard(context, hive),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Big yellow beehive outline illustration
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: const Color(0x80FFF0B3),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: BeehiveIcon(
                  size: 72,
                  roofColor: Color(0xFFFFE082),
                  bodyColor: Color(0xFFFFF9C4),
                  outlineColor: Color(0xFFE6A800),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Hive Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first hive to start\nmonitoring your colonies.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHiveCard(BuildContext context, HiveData hive) {
    final acousticClean = hive.acoustic.trim().toLowerCase();
    final isAcousticNotDetected = acousticClean == '0' ||
        acousticClean == '0 hz' ||
        acousticClean.startsWith('0 ') ||
        hive.acousticStatus.toLowerCase().contains('not detected');

    final conditionText = isAcousticNotDetected ? 'No Buzz Detected' : hive.conditionLabel;
    final conditionBgColor = isAcousticNotDetected ? const Color(0xFFFFEBEE) : hive.labelBgColor;
    final conditionTextColor = isAcousticNotDetected
        ? const Color(0xFFC62828)
        : (hive.labelColor == Colors.grey ? Colors.black87 : hive.labelColor);
    final confidenceText = isAcousticNotDetected ? '0%' : '${hive.confidence}%';
    final confidenceColor = isAcousticNotDetected ? const Color(0xFFD32F2F) : Colors.black;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => HiveDetailScreen(hive: hive),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            // Hive graphic
            const BeehiveIcon(size: 42),
            const SizedBox(width: 12),

            // Hive info
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
                  const SizedBox(height: 4),
                  // Condition status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: conditionBgColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      conditionText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: conditionTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.black54),
                      const SizedBox(width: 4),
                      Text(
                        'Updated: ${hive.updated}',
                        style: const TextStyle(fontSize: 10, color: Colors.black54),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // AI Confidence & Signal
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'AI Confidence',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  confidenceText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: confidenceColor,
                  ),
                ),
                const SizedBox(height: 6),
                _buildSignalBars(hive.signalBars),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalBars(int bars) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final isActive = index < bars;
        final barHeight = 4.0 + (index * 3.0);
        return Container(
          width: 3,
          height: barHeight,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: isActive ? AppColors.healthyGreen : const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
