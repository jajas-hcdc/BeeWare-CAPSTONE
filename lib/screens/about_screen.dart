import 'package:flutter/material.dart';
import '../widgets/honeycomb_scaffold.dart';
import '../widgets/custom_app_bar.dart';

class AboutBeeWareScreen extends StatelessWidget {
  const AboutBeeWareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HoneycombScaffold(
      appBar: const CustomHeaderBar(
        title: 'About BeeWare',
        showBack: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Bee Mascot Logo
              Image.asset(
                'assets/images/bee_mascot_large.png',
                height: 130,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.emoji_nature, size: 90, color: Colors.black),
              ),
              const SizedBox(height: 16),

              const Text(
                'BEEWARE',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Version 1.0.0.0',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'An AI-Enabled IoT Hive\nMonitoring System',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 32),

              const Text(
                'Developed By:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Robles, Joshua\nPugoot, Justine\nLedesma, Earl Andre\nOviedo, Alexa',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
