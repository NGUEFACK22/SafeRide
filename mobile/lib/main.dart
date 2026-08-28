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
import 'screens/rating_screen.dart';
import 'screens/transporteur_dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/profile_edit_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/emergency_contacts_screen.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase absent (ex. google-services.json non fourni) : l'app démarre
    // quand même, le push sera initialisé dès que la configuration existe.
  }
  runApp(const SafeRideApp());
}

class SafeRideApp extends StatelessWidget {
  const SafeRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeRide AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: '/',
      routes: {
        '/': (ctx) => const SplashScreen(),
        '/login': (ctx) => const LoginScreen(),
        '/register': (ctx) => const RegisterScreen(),
        '/home': (ctx) {
          final user = ModalRoute.of(ctx)?.settings.arguments as User?;
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
        '/rating': (ctx) {
          final arg = ModalRoute.of(ctx)?.settings.arguments as Map<String, dynamic>;
          return RatingScreen(trip: arg['trip'], existingRating: arg['existing']);
        },
        '/notifications': (ctx) => const NotificationsScreen(),
        '/admin': (ctx) => const AdminScreen(),
        '/emergency-contacts': (ctx) => const EmergencyContactsScreen(),
        '/transporteur-dashboard': (ctx) => const TransporteurDashboardScreen(),
        '/profile': (ctx) {
          final arg = ModalRoute.of(ctx)?.settings.arguments;
          return ProfileScreen(user: arg as dynamic);
        },
        '/profile-edit': (ctx) => const ProfileEditScreen(),
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
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.shield, size: 36, color: AppTheme.primaryBlue),
            ),
            const SizedBox(height: 16),
            const Text('SafeRide AI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
            const SizedBox(height: 6),
            const Text('Bienvenue sur SafeRide AI', style: TextStyle(color: AppTheme.textGrey)),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: AppTheme.primaryBlue),
          ],
        ),
      ),
    );
  }
}