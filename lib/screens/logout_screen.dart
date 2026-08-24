import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class LogoutScreen extends StatelessWidget {
  const LogoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenYellow,
      appBar: const CustomHeaderBar(
        title: 'Log Out',
        showBack: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Large circular logout badge
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
                  ],
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(80, 80),
                    painter: _LogoutIconPainter(),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              const Text(
                'Log out?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Are you sure you want to\nlog out of your account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 36),

              // Yes, Log Out button (Yellow)
              AppStyles.primaryButton(
                text: 'Yes, Log Out',
                backgroundColor: AppColors.btnYellow,
                textColor: Colors.black,
                onPressed: () async {
                  await AuthService().signOut();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
              ),
              const SizedBox(height: 12),

              // No button (Red)
              AppStyles.primaryButton(
                text: 'No',
                backgroundColor: AppColors.btnRed,
                textColor: Colors.black,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Door bracket (top, left, bottom)
    final doorPath = Path()
      ..moveTo(w * 0.45, h * 0.15)
      ..lineTo(w * 0.2, h * 0.15)
      ..lineTo(w * 0.2, h * 0.85)
      ..lineTo(w * 0.45, h * 0.85);

    canvas.drawPath(doorPath, paint);

    // Arrow line
    canvas.drawLine(
      Offset(w * 0.35, h * 0.5),
      Offset(w * 0.85, h * 0.5),
      paint,
    );

    // Arrow head
    final arrowHead = Path()
      ..moveTo(w * 0.65, h * 0.3)
      ..lineTo(w * 0.85, h * 0.5)
      ..lineTo(w * 0.65, h * 0.7);

    canvas.drawPath(arrowHead, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
