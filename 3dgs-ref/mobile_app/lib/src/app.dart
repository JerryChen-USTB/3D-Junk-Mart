import 'package:flutter/material.dart';

import 'pages/marketplace_shell_page.dart';

class ThreeGsMarketplaceApp extends StatelessWidget {
  const ThreeGsMarketplaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '3DGS Marketplace',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F8B8D),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6F2),
        useMaterial3: true,
      ),
      home: const MarketplaceShellPage(),
    );
  }
}
