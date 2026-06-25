import 'package:flutter/material.dart';

class CustomLoader extends StatefulWidget {
  const CustomLoader({super.key});

  @override
  State<CustomLoader> createState() => _CustomLoaderState();
}

class _CustomLoaderState extends State<CustomLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true); // matches CSS "animation: rotationBack … reverse"
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use the app's primary purple (or any purple you like)
    const Color purple = Color(0xFF381932);
    const Color lightPurple = Color(0xFF5E3A52);

    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // Outer rotating square
          return Transform.rotate(
            angle: _controller.value * 2 * 3.14159, // full rotation
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: lightPurple,
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 5)
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Inner rotated square (45°)
                  Transform.rotate(
                    angle: 0.785398, // 45 degrees in radians
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: purple,
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 5)
                        ],
                      ),
                    ),
                  ),
                  // Central circle
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}