import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_service.dart';
import 'services/project_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AuthService.initialize();
  await AuthService.silentSignIn();
  // Sync projects in background after auth
  if (AuthService.isSignedIn) {
    ProjectService.syncWithSheet(); // fire and forget
  }
  runApp(const MaplewoodApp());
}

class MaplewoodApp extends StatelessWidget {
  const MaplewoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maplewood',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: AuthService.isSignedIn ? const HomeScreen() : const SplashScreen(),
    );
  }
}

/// Tries silent sign-in, then routes to Home or Login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final signedIn = await AuthService.silentSignIn();
    print('Silent sign-in result: $signedIn, user: ${AuthService.currentUser?.displayName}');
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => signedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
