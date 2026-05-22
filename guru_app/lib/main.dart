import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

// Screens
import 'features/auth/onboarding_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/scheduler/schedule_screen.dart';
import 'features/calls/call_screen.dart';
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
      child: const GuruApp(),
    ),
  );
}

class GuruApp extends ConsumerWidget {
  const GuruApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly watch syncServiceProvider to start background sync loop
    ref.watch(syncServiceProvider);

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'WTF Guru App',
      theme: AppTheme.getTheme(false), // Guru App Member (Blue) Theme
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.watch(authServiceProvider);

  return GoRouter(
    initialLocation: authService.isOnboardingCompleted ? '/' : '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/schedule',
        builder: (context, state) => const ScheduleCallScreen(),
      ),
      GoRoute(
        path: '/sessions',
        builder: (context, state) => const SessionsScreen(),
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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    final upcomingCall = ref.watch(upcomingCallProvider);
    final authService = ref.watch(authServiceProvider);

    final trainer = authService.getSeededTrainers().firstWhere(
      (t) => t.id == (currentUser?.assignedTrainerId ?? 'aarav_trainer'),
      orElse: () => authService.getSeededTrainers().first,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guru Dashboard'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16.0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.guruPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.guruPrimary.withOpacity(0.3)),
            ),
            child: Text(
              'Member • ${currentUser?.name ?? "DK"}',
              style: const TextStyle(
                color: AppColors.guruPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Section
                  Text(
                    'Hello, ${currentUser?.name ?? "DK"}! 👋',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Welcome back to your fitness training center.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Upcoming Call Card
                  if (upcomingCall != null) ...[
                    _buildUpcomingCallBanner(context, upcomingCall),
                    const SizedBox(height: 24),
                  ],

                  // Grid of 3 Navigation Cards
                  const Text(
                    'Training Portal',
                    style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  
                  _buildActionCard(
                    context,
                    title: 'Chat with Trainer',
                    subtitle: 'Message ${trainer.name}',
                    icon: Icons.chat_bubble,
                    color: AppColors.guruPrimary,
                    badge: unreadCount > 0 ? '$unreadCount' : null,
                    onTap: () => context.push('/chat'),
                  ),
                  const SizedBox(height: 12),
                  
                  _buildActionCard(
                    context,
                    title: 'Schedule a Call',
                    subtitle: 'Select available blocks',
                    icon: Icons.calendar_today,
                    color: AppColors.warning,
                    onTap: () => context.push('/schedule'),
                  ),
                  const SizedBox(height: 12),
                  
                  _buildActionCard(
                    context,
                    title: 'My Session Logs',
                    subtitle: 'View ratings and notes',
                    icon: Icons.history,
                    color: AppColors.success,
                    onTap: () => context.push('/sessions'),
                  ),

                  const SizedBox(height: 32),
                  
                  // Active Requests Panel
                  _buildMyRequestsList(context, ref),
                ],
              ),
            ),
          ),
          
          // Debug Overlay DevPanel
          const DevPanelOverlay(),
        ],
      ),
    );
  }

  Widget _buildUpcomingCallBanner(BuildContext context, CallRequest call) {
    final timeStr = DateFormat('h:mm a').format(call.scheduledFor);
    
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.guruPrimary, AppColors.guruPrimary.withBlue(250)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.guruPrimary.withOpacity(0.3),
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
                'UPCOMING SESSION NOW ACTIVE',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Live Workout & Consulting Call',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          Text(
            'Scheduled for today at $timeStr',
            style: const TextStyle(color: Colors.white70, fontSize: 13.0),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              context.push('/call/${call.id}');
            },
            icon: const Icon(Icons.videocam, color: AppColors.guruPrimary),
            label: const Text('Join Call', style: TextStyle(color: AppColors.guruPrimary)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.guruPrimary,
              elevation: 0,
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: AppColors.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13.0, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold),
                  ),
                ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyRequestsList(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(callRequestsProvider).where((r) => r.status != CallRequestStatus.approved).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'My Requests',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        if (requests.isEmpty)
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text(
                'No pending requests.',
                style: TextStyle(color: AppColors.textMuted, fontStyle: FontStyle.italic),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              final dateStr = DateFormat('MMM d, h:mm a').format(req.scheduledFor);
              
              String statusText = 'Pending';
              Color statusColor = AppColors.warning;
              
              if (req.status == CallRequestStatus.declined) {
                statusText = 'Declined';
                statusColor = AppColors.error;
              } else if (req.status == CallRequestStatus.cancelled) {
                statusText = 'Cancelled';
                statusColor = AppColors.textMuted;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateStr,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        if (req.note.isNotEmpty)
                          Text(
                            req.note,
                            style: const TextStyle(fontSize: 12.0, color: AppColors.textSecondary),
                          ),
                        if (req.status == CallRequestStatus.declined && req.declineReason != null)
                          Text(
                            'Reason: ${req.declineReason}',
                            style: const TextStyle(fontSize: 11.0, color: AppColors.error, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
