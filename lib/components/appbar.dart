import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Header extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final Color backButtonColor;

  const Header({
    super.key,
    this.showBackButton = false,
    this.backButtonColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 1,
      centerTitle: true,
      automaticallyImplyLeading: false, // Prevent default back button
      leading:
          showBackButton
              ? IconButton(
                icon: const Icon(Icons.arrow_back),
                color: backButtonColor,
                onPressed: () => Navigator.pop(context),
              )
              : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'lib/images/Logo1.png',
            height: 60,
            errorBuilder:
                (context, error, stackTrace) =>
                    const Icon(Icons.image_not_supported),
          ),
          Text(
            "Fitpose",
            style: GoogleFonts.poppins(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(70);
}
