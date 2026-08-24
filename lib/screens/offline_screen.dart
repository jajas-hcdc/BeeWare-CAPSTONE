import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../widgets/honeycomb_scaffold.dart';

class OfflineScreen extends StatefulWidget {
  final VoidCallback? onRetry;

  const OfflineScreen({super.key, this.onRetry});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  bool _isLoading = false;

  Future<void> _handleReconnect() async {
    setState(() => _isLoading = true);

    final isOnline = await ConnectivityService().checkConnection();

    if (mounted) {
      setState(() => _isLoading = false);
      if (isOnline) {
        widget.onRetry?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still offline. Please check your Wi-Fi or mobile data.'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.black87,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return HoneycombScaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Cloud Off Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    size: 110,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),

                // Main Title
                const Text(
                  'You are offline',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle
                const Text(
                  'Unable to fetch data.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),

                // Last Synced Info
                AnimatedBuilder(
                  animation: ConnectivityService(),
                  builder: (context, child) {
                    final timeAgo = ConnectivityService().lastSyncedFormatted;
                    return Text(
                      'Last Synced:\n$timeAgo',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),

                // Reconnect Button
                SizedBox(
                  width: 260,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCC00),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Colors.black, width: 1.4),
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleReconnect,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : const Text(
                            'Reconnect',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
