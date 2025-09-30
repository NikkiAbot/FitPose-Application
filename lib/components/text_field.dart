import 'package:flutter/material.dart';

class TextWidget extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;

  const TextWidget({
    super.key,
    required this.controller,
    required this.hintText,
    required this.obscureText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 25),
      child: TextField(
        obscureText: obscureText,
        controller: controller,
        decoration: InputDecoration(
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color.fromARGB(255, 164, 164, 164)),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          fillColor: Colors.grey,
          filled: true,
          hintText: hintText,
        ),
      ),
    );
  }
}
