import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const ShadowPlayer());

class ShadowPlayer extends StatelessWidget {
  const ShadowPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0B0B), // Deep Black
        primaryColor: const Color(0xFFBD0B11),           // Chaos Red
        textTheme: GoogleFonts.orbitronTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFBD0B11).withOpacity(0.2), Colors.transparent],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "SHADOW PLAYER",
                style: TextStyle(
                  color: Color(0xFFBD0B11),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 60),
              // Glowing "Chaos Emerald" Play Button
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFBD0B11).withOpacity(0.7),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: IconButton(
                  iconSize: 120,
                  icon: const Icon(Icons.play_circle_filled, color: Colors.white),
                  onPressed: () {
                    print("Chaos Control initiated!");
                  },
                ),
              ),
              const SizedBox(height: 60),
              const Text(
                "READY TO RUN",
                style: TextStyle(color: Colors.white30, letterSpacing: 4, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}