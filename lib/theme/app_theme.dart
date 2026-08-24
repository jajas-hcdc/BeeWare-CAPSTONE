import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryYellow = Color(0xFFFFCC00);
  static const Color accentYellow = Color(0xFFFFD700);
  static const Color darkYellow = Color(0xFFF5B800);
  static const Color screenYellow = Color(0xFFFFD13B);
  static const Color scaffoldBg = Color(0xFFFFD23F);

  static const Color cardWhite = Colors.white;
  static const Color textBlack = Color(0xFF1A1A1A);
  static const Color textMuted = Color(0xFF757575);
  static const Color borderBlack = Colors.black;

  // Status & condition colors
  static const Color healthyGreen = Color(0xFF34C759);
  static const Color healthyGreenBg = Color(0xFFD4F7DC);
  static const Color stressYellow = Color(0xFFFFCC00);
  static const Color stressYellowBg = Color(0xFFFFF3CD);
  static const Color swarmingRed = Color(0xFFFF4B4B);
  static const Color swarmingRedBg = Color(0xFFFFDADA);
  static const Color queenlessRed = Color(0xFFFF4B4B);
  static const Color queenlessRedBg = Color(0xFFFFDADA);
  static const Color infoBlue = Color(0xFF3B82F6);
  static const Color infoBlueBg = Color(0xFFC7E2FE);

  // Queen Status Specific Colors
  static const Color queenPresentGreen = Color(0xFF2E7D32);
  static const Color queenPresentGreenBg = Color(0xFFD4F7DC);
  static const Color queenAbsentRed = Color(0xFFD32F2F);
  static const Color queenAbsentRedBg = Color(0xFFFFDADA);
  static const Color queenAcceptedBlue = Color(0xFF1976D2);
  static const Color queenAcceptedBlueBg = Color(0xFFC7E2FE);
  static const Color queenRejectedOrange = Color(0xFFE65100);
  static const Color queenRejectedOrangeBg = Color(0xFFFFE0B2);

  // Button colors
  static const Color btnYellow = Color(0xFFFFC600);
  static const Color btnRed = Color(0xFFFF4D4D);
}

class AppStyles {
  static BoxDecoration cardDecoration({
    Color color = Colors.white,
    BorderRadius? borderRadius,
    Color borderColor = Colors.black,
    double borderWidth = 1.2,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: const [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 3,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  static InputDecoration inputDecoration({
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF9E9E9E),
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.black, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.black, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 2.0),
      ),
    );
  }

  static Widget primaryButton({
    required String text,
    required VoidCallback? onPressed,
    Color backgroundColor = AppColors.btnYellow,
    Color textColor = Colors.black,
    double height = 50,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.black, width: 1.5),
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
            : Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
