import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/honeycomb_scaffold.dart';

class LoggingInScreen extends StatefulWidget {
  final Future<void> Function()? onAuthenticate;

  const LoggingInScreen({super.key, this.onAuthenticate});

  @override
  State<LoggingInScreen> createState() => _LoggingInScreenState();
}

class _LoggingInScreenState extends State<LoggingInScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _progressAnimation;
  late int _factIndex;

  final List<String> _facts = [
    'A queen bee can lay up to 2,000 eggs in a single day during peak season.',
    'Bees communicate with each other by doing a "waggle dance".',
    'Honey bees are the only insect that produces food consumed by humans.',
    'A single worker bee produces about 1/12th of a teaspoon of honey in her lifetime.',
    'Bees have 5 eyes: 2 large compound eyes and 3 smaller ocelli on top of their head.',
    'A honey bee flies at a speed of about 15 miles per hour.',
    'Bees pollinate 1 out of every 3 bites of food that we eat.',
  ];

  @override
  void initState() {
    super.initState();
    _factIndex = Random().nextInt(_facts.length);

    // 2.5 second smooth progress animation
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _progressAnimation = Tween<double>(begin: 0.05, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _animController.forward();
    _startProcess();
  }

  Future<void> _startProcess() async {
    final startTime = DateTime.now();

    try {
      if (widget.onAuthenticate != null) {
        await widget.onAuthenticate!();
      }

      // Ensure at least 2.5 seconds total elapsed time so user sees the progress bar
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed < 2500) {
        await Future.delayed(Duration(milliseconds: 2500 - elapsed));
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(e);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheAssets();
  }

  void _precacheAssets() {
    try {
      precacheImage(const AssetImage('assets/images/honeycomb_bg.jpg'), context);
      precacheImage(const AssetImage('assets/images/loading_bee.png'), context);
      precacheImage(const AssetImage('assets/images/bee_icon.png'), context);
    } catch (_) {}
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HoneycombScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Logging in. . .',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 36),

              // Animated bee progress bar with flying bee
              SizedBox(
                width: 270,
                height: 46,
                child: AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    final progress = _progressAnimation.value.clamp(0.0, 1.0);
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Track
                        Positioned(
                          top: 10,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(220),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFCC00),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Moving Bee Mascot
                        Positioned(
                          left: (progress * 222).clamp(0.0, 222.0),
                          top: -2,
                          child: Image.asset(
                            'assets/images/loading_bee.png',
                            height: 48,
                            width: 48,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Text('🐝', style: TextStyle(fontSize: 28)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),

              // Trivia Section (Clean design directly on the screen)
              Column(
                children: [
                  const Text(
                    'Did you know?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      _facts[_factIndex],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
