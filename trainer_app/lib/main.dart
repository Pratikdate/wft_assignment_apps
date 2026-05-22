import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

// Screens
import 'features/auth/login_screen.dart';
import 'features/calls/call_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/members/members_screen.dart';
import 'features/requests/requests_screen.dart';
import 'features/sessions/sessions_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Open all required Hive boxes
  await Hive.openBox(AuthService.boxName);
  await Hive.openBox(SyncService.messagesBoxName);
  await Hive.openBox(SyncService.callsBoxName);
  await Hive.openBox(SyncService.sessionsBoxName);
  await Hive.openBox(SyncService.roomsBoxName);

  final authService = AuthService();
  await authService.init();

  runApp(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
      ],
      child: const TrainerApp(),
    ),
  );
}

class TrainerApp extends ConsumerWidget {
  const TrainerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly watch syncServiceProvider to start background sync loop
    ref.watch(syncServiceProvider);

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'WTF Trainer App',
      theme: AppTheme.getTheme(true), // Trainer App (Red) Theme
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.watch(authServiceProvider);

  return GoRouter(
    initialLocation: authService.currentUser != null ? '/' : '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/call/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CallScreen(requestId: id);
        },
      ),
    ],
  );
});

// Dashboard State Provider for tracking active tab
final activeTabProvider = StateProvider<int>((ref) => 0);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeTabProvider);
    final currentUser = ref.watch(currentUserProvider);
    final upcomingCall = ref.watch(upcomingCallProvider);
    final requests = ref.watch(callRequestsProvider);
    
    final pendingCount = requests.where((r) => r.status == CallRequestStatus.pending).length;

    // Body screens mapping
    final List<Widget> screens = [
      const MembersScreen(),
      const RequestsScreen(),
      const SessionsScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Custom top header for branding
                _buildHeader(context, currentUser),
                
                // Upcoming session call banner if active
                if (upcomingCall != null)
                  _buildUpcomingCallBanner(context, upcomingCall),
                
                // Tab view area
                Expanded(
                  child: screens[activeTab],
                ),
              ],
            ),
          ),
          
          // Debug Overlay DevPanel
          const DevPanelOverlay(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: activeTab,
        onDestinationSelected: (index) {
          ref.read(activeTabProvider.notifier).state = index;
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Members',
          ),
          NavigationDestination(
            icon: Badge(
              label: pendingCount > 0 ? Text('$pendingCount') : null,
              isLabelVisible: pendingCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              label: pendingCount > 0 ? Text('$pendingCount') : null,
              isLabelVisible: pendingCount > 0,
              child: const Icon(Icons.notifications),
            ),
            label: 'Requests',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Sessions',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, User? currentUser) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      color: AppColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WTF Trainer Hub',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Aarav\'s Client Management',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.trainerPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.trainerPrimary.withOpacity(0.3)),
            ),
            child: Text(
              'Trainer • ${currentUser?.name.split(' ').first ?? "Aarav"}',
              style: const TextStyle(
                color: AppColors.trainerPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildUpcomingCallBanner(BuildContext context, CallRequest call) {
    final timeStr = DateFormat('h:mm a').format(call.scheduledFor);
    
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.trainerPrimary, Color(0xffB80610)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.trainerPrimary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.videocam, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'ACTIVE WORKOUT CALL AVAILABLE',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Live Member Consultation Call (DK)',
            style: TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.bold),
          ),
          Text(
            'Scheduled for today at $timeStr',
            style: const TextStyle(color: Colors.white70, fontSize: 12.0),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              context.push('/call/${call.id}');
            },
            icon: const Icon(Icons.videocam, color: AppColors.trainerPrimary),
            label: const Text('Join Consultation Call', style: TextStyle(color: AppColors.trainerPrimary)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.trainerPrimary,
              elevation: 0,
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
      ),
    );
  }
}
