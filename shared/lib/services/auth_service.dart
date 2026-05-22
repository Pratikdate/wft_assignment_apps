import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user.dart';
import '../utils/logger.dart';

class AuthService {
  static const String boxName = 'auth_box';
  late Box _box;

  Future<void> init() async {
    _box = await Hive.openBox(boxName);
    AppLogger.auth('AuthService initialized');
  }

  bool get isOnboardingCompleted => 
      _box.get('onboarding_completed', defaultValue: false) as bool;

  Future<void> setOnboardingCompleted(bool completed) async {
    await _box.put('onboarding_completed', completed);
    AppLogger.auth('Onboarding completed state updated: $completed');
  }

  User? get currentUser {
    final userJson = _box.get('current_user');
    if (userJson == null) return null;
    try {
      final map = Map<String, dynamic>.from(userJson as Map);
      return User.fromJson(map);
    } catch (e) {
      AppLogger.auth('Error decoding current user: $e');
      return null;
    }
  }

  Future<void> setCurrentUser(User? user) async {
    if (user == null) {
      await _box.delete('current_user');
      AppLogger.auth('Current user logged out');
    } else {
      await _box.put('current_user', user.toJson());
      AppLogger.auth('User logged in: ${user.name} (${user.role.name})');
    }
  }

  List<User> getSeededTrainers() {
    return [
      User(
        id: 'aarav_trainer',
        role: UserRole.trainer,
        name: 'Aarav (Lead Trainer)',
        email: 'aarav@wtf.fit',
        avatarUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=150&q=80',
      ),
      User(
        id: 'marcus_trainer',
        role: UserRole.trainer,
        name: 'Marcus (Strength Coach)',
        email: 'marcus@wtf.fit',
        avatarUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&w=150&q=80',
      ),
      User(
        id: 'priya_trainer',
        role: UserRole.trainer,
        name: 'Priya (Nutritionist)',
        email: 'priya@wtf.fit',
        avatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=150&q=80',
      ),
    ];
  }

  User getSeededMemberDK(String trainerId) {
    return User(
      id: 'dk_member',
      role: UserRole.member,
      name: 'DK',
      email: 'dk@wtf.fit',
      avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80',
      assignedTrainerId: trainerId,
    );
  }

  User getSeededTrainerAarav() {
    return getSeededTrainers().first;
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  // Override this in main.dart after initializing the service
  throw UnimplementedError('authServiceProvider must be overridden');
});

final currentUserProvider = StateProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.currentUser;
});
