import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class UserGuideScreen extends StatefulWidget {
  const UserGuideScreen({super.key});

  @override
  State<UserGuideScreen> createState() => _UserGuideScreenState();
}

class _UserGuideScreenState extends State<UserGuideScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Getting Started',
    'AI Diagnostics',
    'IoT Pairing',
    'Alerts & Reports'
  ];

  final List<Map<String, dynamic>> _guides = [
    {
      'title': '1. Getting Started with BeeWare',
      'category': 'Getting Started',
      'icon': Icons.rocket_launch_outlined,
      'summary': 'Learn the basics of dashboard navigation, profile customization, and live apiary health monitoring.',
      'steps': [
        'Home Dashboard: View your Overall Apiary Health Score, active vs. alert colony counts, live sensor averages, and recent alerts.',
        'Custom Nickname & Photo: Tap your profile card in Settings (or Management > User Profile) to customize your nickname, pick an avatar, or upload a photo from your camera or gallery.',
        'Dynamic Greetings: The home screen greets you based on your phone\'s local time (Morning, Afternoon, Evening).',
        'Cloud & Offline Sync: Your profile, paired hives, and telemetry history are saved locally on your device and synced with Firebase.',
      ],
    },
    {
      'title': '2. Pairing ESP32 IoT Nodes (Auto-Detect & QR)',
      'category': 'IoT Pairing',
      'icon': Icons.qr_code_scanner,
      'summary': 'Connect your ESP32 sensor node using live Wi-Fi Auto-Detection or by scanning the hive QR sticker.',
      'steps': [
        'Power on your ESP32 node (via USB or battery). Once connected to Wi-Fi, it automatically streams telemetry to the cloud.',
        'In the "My Hives" tab, tap the "+" icon in the top-right corner to open the "Add New Hive" menu.',
        'Option A — Auto-Detect Online Node: Automatically lists active ESP32 nodes currently powered on and transmitting live data. Tap a discovered node to name and pair it.',
        'Option B — Scan Hive QR Sticker: Point your camera at the physical QR sticker on the hive box to pair and name your hive immediately.',
        'Download QR Sticker: Open any paired hive and tap the QR icon in the top-right header to preview, download, or share its printable QR sticker.',
      ],
    },
    {
      'title': '3. Understanding AI Colony Health Diagnostics',
      'category': 'AI Diagnostics',
      'icon': Icons.psychology_outlined,
      'summary': 'How the acoustic machine learning model and sensors classify queen presence, colony states, and hardware status.',
      'steps': [
        'Queen Present (🟢): Stable worker humming (100–290 Hz) and steady brood thermoregulation (32°C – 36°C). Colony is healthy and queenright.',
        'Queen Absent (🔴): Agitated queenless roar or piping frequencies (>300 Hz) with fluctuating cluster temperature. Immediate frame inspection recommended.',
        'Queen Accepted (🔵): Colony piping harmony confirmed after introducing a newly mated queen. Avoid disturbing the brood box for 5 days.',
        'Queen Rejected (🟠): High-agitation buzzing detected as workers ball or reject an introduced queen cage. Inspect the release cage immediately.',
        'No Buzz / Sensor Alerts (⚠️): If the microphone records 0 Hz (silence) or the sensor reports 0.0°C / 0%, a Sensor Not Detected banner appears to alert you.',
      ],
    },
    {
      'title': '4. Interactive History Charts & Buzz Audio Playback',
      'category': 'AI Diagnostics',
      'icon': Icons.show_chart,
      'summary': 'Explore multi-day temperature, humidity, and acoustic charts, plus play back recorded hive buzz clips.',
      'steps': [
        'Open any hive from "My Hives" and tap or swipe to the "History" tab.',
        'Switch between "24 Hours", "7 Days", and "30 Days" timeframes using the top selector bar.',
        'Horizontal Swiping: Swipe left and right inside the Temperature, Humidity, and Acoustic charts to view earlier dates, and tap data points to inspect exact values.',
        'Recent Hive Buzz Recordings: Listen to the latest 5-second WAV audio clips captured by the ESP32 microphone directly inside the History tab, complete with timestamps and trigger badges.',
      ],
    },
    {
      'title': '5. Smart Alerts & Notification Settings',
      'category': 'Alerts & Reports',
      'icon': Icons.notifications_active_outlined,
      'summary': 'Real-time anomaly alerts for queen loss, temperature/humidity extremes, and notification controls.',
      'steps': [
        'Live Hardware Verification: Notifications only trigger when an ESP32 node is actively powered on and streaming fresh telemetry — preventing false alarms when devices are unplugged.',
        'High-Priority Alarms: Critical conditions (Queen Absent, Queen Rejected, temperature outside 32°C–36°C, humidity outside 50%–70%, or 0 Hz silence) trigger system notifications and in-app banners.',
        '1-Tap Deep Linking: Tapping any notification or selecting an alert in the "Alerts" tab opens the detailed diagnostic view and lets you jump directly to that hive.',
        'Notification Toggles: Go to Settings > Notification Settings to independently enable or disable Push Notifications and Alert Notifications.',
      ],
    },
    {
      'title': '6. Exporting Health Audits & CSV Telemetry',
      'category': 'Alerts & Reports',
      'icon': Icons.picture_as_pdf_outlined,
      'summary': 'Generate printable colony health audit reports and raw CSV spreadsheets for research or inspection.',
      'steps': [
        'Open any hive detail screen, go to the "History" tab, and tap the Share / Export button next to the timeframe selector.',
        'Choose "Export Health Audit (PDF/Txt)" for a formatted report containing AI diagnosis, sensor readings, and actionable recommendations.',
        'Choose "Export CSV Data" to export raw historical temperature, humidity, acoustic, and condition logs for Excel or Google Sheets.',
      ],
    },
    {
      'title': '7. Managing Hives & Account Settings',
      'category': 'Getting Started',
      'icon': Icons.tune_rounded,
      'summary': 'Rename or remove paired hives, update your account password, and manage app preferences.',
      'steps': [
        'Hive Management: In the "My Hives" tab, tap the sliders icon in the top-right corner (or long-press a hive card) to rename a hive or delete it from your apiary.',
        'Account Security: Go to Settings > Management > Change password to update your login credentials.',
        'Offline Indicator: When a paired ESP32 node is unplugged or loses Wi-Fi, its card displays an "Offline" badge and last-seen timestamp.',
      ],
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _guides.where((g) {
      final matchesCategory = _selectedCategory == 'All' || g['category'] == _selectedCategory;
      final matchesQuery = _searchQuery.isEmpty ||
          g['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          g['summary'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesQuery;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: const CustomHeaderBar(
        title: 'App User Guide',
        showBack: true,
      ),
      body: Column(
        children: [
          // Search Header
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
                  const Icon(Icons.search, color: Colors.black54, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: const TextStyle(fontSize: 13, color: Colors.black),
                      decoration: const InputDecoration(
                        hintText: 'Search guides and tutorials...',
                        hintStyle: TextStyle(color: Colors.black45, fontSize: 13),
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
                      child: const Icon(Icons.clear, size: 18, color: Colors.black54),
                    ),
                ],
              ),
            ),
          ),

          // Category Pills
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: _categories.length,
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFFFFCC00),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: isSelected ? Colors.black : Colors.black26,
                      width: isSelected ? 1.4 : 1,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _selectedCategory = cat);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Guides List
          Expanded(
            child: filtered.isNotEmpty
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _guideAccordion(item);
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.search_off, size: 48, color: Colors.black38),
                        SizedBox(height: 10),
                        Text('No guides match your search', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _guideAccordion(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: AppStyles.cardDecoration(borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
          childrenPadding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFCC00),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black, width: 1.2),
            ),
            child: Icon(item['icon'] as IconData, color: Colors.black, size: 22),
          ),
          title: Text(
            item['title'],
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              item['summary'],
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          children: [
            const Divider(height: 16, color: Colors.black12),
            ...List.generate((item['steps'] as List<String>).length, (i) {
              final step = (item['steps'] as List<String>)[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEEEE),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black87, width: 1),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step,
                        style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
