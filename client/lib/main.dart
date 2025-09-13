import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qypxekyjsdzbobmirznk.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF5cHhla3lqc2R6Ym9ibWlyem5rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc3MjI2MzMsImV4cCI6MjA3MzI5ODYzM30.tRoAZvFJp8W5r5vy5AwXlggEkljPpvt0_-T4i6OmnZE',
  );
  runApp(const EcoActionApp());
}

class EcoActionApp extends StatelessWidget {
  const EcoActionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoAction',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}