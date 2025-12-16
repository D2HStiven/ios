import 'package:flutter/material.dart';
import 'dart:async';

class SplashPage extends StatefulWidget {
  final Widget nextPage;
  const SplashPage({super.key, required this.nextPage});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => widget.nextPage),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rojoSuave = Colors.red.shade50;
    final rojoPrincipal = Colors.red.shade400;

    return Scaffold(
      backgroundColor: rojoSuave,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: 1.2,
              duration: const Duration(seconds: 2),
              curve: Curves.easeInOut,
              child: Image.asset('assets/images/logo.png', width: 140),
            ),
            const SizedBox(height: 30),
            Text(
              'Bienvenido a',
              style: TextStyle(fontSize: 20, color: Colors.grey.shade800),
            ),
            Text(
              'Servicios JR App',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: rojoPrincipal,
              ),
            ),
            const SizedBox(height: 40),
            CircularProgressIndicator(color: rojoPrincipal),
          ],
        ),
      ),
    );
  }
}
