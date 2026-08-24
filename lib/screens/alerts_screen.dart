import 'package:flutter/material.dart';
import '../models/alert_model.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import 'alert_details_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  int _selectedFilter = 0;
  late final PageController _pageController;
  final List<String> _filterTabs = ['All', 'Critical', 'Warning'];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedFilter);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_selectedFilter != index) {
      setState(() => _selectedFilter = index);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AlertService(),
      builder: (context, child) {
        final allAlerts = AlertService().alerts;
        final criticalAlerts = allAlerts.where((a) => a.severity.toLowerCase() == 'critical').toList();
        final warningAlerts = allAlerts.where((a) => a.severity.toLowerCase() == 'warning').toList();

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
                    'Alerts',
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
          body: Column(
            children: [
              // Filter Tabs
              Container(
                color: AppColors.screenYellow,
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(_filterTabs.length, (index) {
                    final isSelected = index == _selectedFilter;
                    return GestureDetector(
                      onTap: () => _onTabTapped(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          border: isSelected
                              ? const Border(
                                  bottom: BorderSide(color: Colors.black, width: 2.5),
                                )
                              : null,
                        ),
                        child: Text(
                          _filterTabs[index],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Alerts PageView with slide/swipe gesture support
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _selectedFilter = index);
                  },
                  children: [
                    _buildAlertsList(context, allAlerts),
                    _buildAlertsList(context, criticalAlerts),
                    _buildAlertsList(context, warningAlerts),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlertsList(BuildContext context, List<AlertModel> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'No alerts in this category.',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final alert = list[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _buildAlertCard(context, alert),
        );
      },
    );
  }

  Widget _buildAlertCard(BuildContext context, AlertModel alert) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AlertDetailsScreen(data: alert),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14.0),
        decoration: AppStyles.cardDecoration(
          color: alert.severityBgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(alert.iconData, size: 32, color: alert.severityColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.hiveId,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alert.message,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              alert.timeFormatted,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
