import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'models/trip.dart';
import 'models/user.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/lost_item_screen.dart';
import 'screens/manager_screen.dart';
import 'screens/register_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/sos_button_screen.dart';
import 'screens/trip_active_screen.dart';
import 'screens/ai_screen.dart';
import 'screens/vehicles_screen.dart';
import 'screens/dispute_screen.dart';
import 'screens/identity_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/trip_map_screen.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SafeRideApp());
}

class SafeRideApp extends StatelessWidget {
  const SafeRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeRide AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20)),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (ctx) => const SplashScreen(),
        '/login': (ctx) => const LoginScreen(),
        '/register': (ctx) => const RegisterScreen(),
        '/home': (ctx) {
          final user = ModalRoute.of(ctx)?.settings.arguments as User;
          return HomeScreen(user: user);
        },
        '/scan': (ctx) => const ScanScreen(),
        '/trip-active': (ctx) {
          final arg = ModalRoute.of(ctx)?.settings.arguments;
          return TripActiveScreen(initialTrip: arg as Trip?);
        },
        '/sos-button': (ctx) {
          final arg = ModalRoute.of(ctx)?.settings.arguments;
          return SosButtonScreen(trip: arg as Trip?);
        },
        '/history': (ctx) => const HistoryScreen(),
        '/lost-item': (ctx) => const LostItemScreen(),
        '/dispute': (ctx) => const DisputeScreen(),
        '/vehicles': (ctx) => const VehiclesScreen(),
        '/manager': (ctx) => const ManagerScreen(),
        '/ai': (ctx) => const AiScreen(),
        '/identity': (ctx) => const IdentityScreen(),
        '/trip-map': (ctx) {
          final arg = ModalRoute.of(ctx)?.settings.arguments;
          return TripMapScreen(tripId: arg as int);
        },
        '/notifications': (ctx) => const NotificationsScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.delayed(const Duration(milliseconds: 600));
    final User? user = await _auth.currentUser();
    try {
      await PushService.instance.init();
    } catch (_) {
      // Push indisponible (ex. Firebase non configuré) : l'app continue.
    }
    if (!mounted) return;
    if (user != null) {
      Navigator.of(context).pushReplacementNamed('/home', arguments: user);
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shield,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'SafeRide AI',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}