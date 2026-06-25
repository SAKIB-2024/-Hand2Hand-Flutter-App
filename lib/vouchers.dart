import 'package:flutter/material.dart';

class VouchersPage extends StatelessWidget {
  const VouchersPage({super.key});
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Vouchers'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text('Vouchers – Coming Soon', style: TextStyle(fontSize: 18)),
      ),
    );
  }
}