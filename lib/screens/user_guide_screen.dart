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
      'summary': 'Learn the basics of navigation, profile customization, and home screen health overview.',
      'steps': [
        'Home Dashboard: View your Overall Apiary Health Score and live sensor averages.',
        'Custom Nickname & Photo: Tap your profile image to customize your nickname and upload real photos using your camera or gallery.',
        'Dynamic Greetings: The app greets you based on your phone\'s local time (Morning, Afternoon, Evening).',
        'Offline Support: Your custom profile and telemetry are saved securely on your device.',
      ],
    },
    {
      'title': '2. Pairing ESP32 IoT Nodes via BLE',
      'category': 'IoT Pairing',
      'icon': Icons.bluetooth_searching,
      'summary': 'Connect your physical sensor box (ESP32 + INMP441 + DHT22) to Wi-Fi or mobile hotspots without a computer.',
      'steps': [
        'Power on your ESP32 node (via 18650 battery or USB).',
        'In the "Hives" tab, tap the "+" icon and choose "Pair IoT Node (BLE SmartConfig)".',
        'Wait for the BLE radar to discover your node (e.g. BeeWare-Node-001) and select it.',
        'Enter your 2.4GHz Wi-Fi SSID or Phone\'s Mobile Hotspot name and password.',
        'Tap "Send to ESP32". The app will upload credentials, verify the internet link, and automatically create your new hive!',
      ],
    },
    {
      'title': '3. Understanding AI Colony Health Diagnostics',
      'category': 'AI Diagnostics',
      'icon': Icons.psychology_outlined,
      'summary': 'How the acoustic machine learning model classifies queen presence and colony states.',
      'steps': [
        'Queen Present (🟢): Stable worker humming (~180-250 Hz) and steady brood thermoregulation (34°C - 36°C).',
        'Queen Absent (🔴): Agitated piping/fanning frequencies (>300 Hz) with fluctuating cluster temperature. Immediate physical inspection recommended.',
        'Queen Accepted (🔵): Colony has successfully integrated a newly introduced mated queen.',
        'Queen Rejected (🟠): Workers are balling or rejecting an introduced queen cage. Remove cage and re-evaluate.',
      ],
    },
    {
      'title': '4. Interactive History Charts & Sensor Swiping',
      'category': 'AI Diagnostics',
      'icon': Icons.show_chart,
      'summary': 'Explore historical multi-day temperature, humidity, and acoustic curves.',
      'steps': [
        'Open any hive from "My Hives" and tap the "History" tab.',
        'Switch between 24-Hour, 7-Day, and 30-Day timeframes using the top filter pills.',
        'Horizontal Swiping: Swipe left and right inside the chart box to see earlier dates and historical records.',
        'Tap individual data points on the graph to inspect exact temperature or humidity values at that hour.',
      ],
    },
    {
      'title': '5. Urgent Push Notifications & Lock Screen Deep Linking',
      'category': 'Alerts & Reports',
      'icon': Icons.notifications_active_outlined,
      'summary': 'Real-time emergency alarms for queen loss, extreme temperatures, and swarming.',
      'steps': [
        'High-Priority Alarms: Critical alerts (Queen Absent, T > 37°C, Battery < 15%) trigger instant sound and vibration.',
        '1-Tap Deep Linking: Tapping any notification banner on your lock screen immediately opens that specific hive\'s AI analysis screen.',
        'In-App Heads-Up Banner: If an alert occurs while using the app, a banner drops down with an "Inspect" shortcut.',
      ],
    },
    {
      'title': '6. Exporting PDF Health Audits & CSV Telemetry',
      'category': 'Alerts & Reports',
      'icon': Icons.picture_as_pdf_outlined,
      'summary': 'Generate professional apiary health audits to share with mentors, farm owners, or inspectors.',
      'steps': [
        'Open any hive detail screen and tap the "Export" or share action.',
        'Choose "Export Health Audit PDF" for a printable formatted summary with diagnosis and recommendations.',
        'Choose "Export CSV" for raw spreadsheet telemetry data for research and analytics.',
      ],
    },
    {
      'title': '7. Field Power & Migratory Colony Tips',
      'category': 'IoT Pairing',
      'icon': Icons.solar_power_outlined,
      'summary': 'Best practices for powering mobile hives in remote fields without AC outlets.',
      'steps': [
        'Recommended Power: 1x or 2x 18650 Li-Ion batteries (3.7V 3000mAh) paired with a small 2W solar panel on the hive lid.',
        'Deep Sleep Mode: The ESP32 draws only 15µA in sleep mode, enabling 3 to 4 months of battery life on a single charge.',
        'Weatherproofing: Keep the ESP32 in an IP65 waterproof junction box mounted on the rear of the hive box.',
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
