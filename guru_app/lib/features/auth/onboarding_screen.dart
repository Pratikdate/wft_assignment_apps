import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController(text: 'DK');
  final TextEditingController _emailController = TextEditingController(text: 'dk@wtf.fit');
  
  User? _selectedTrainer;
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trainers = ref.read(authServiceProvider).getSeededTrainers();
    _selectedTrainer ??= trainers.first; // Default selection

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildWelcomeSlide(),
                  _buildProfileSlide(trainers),
                ],
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSlide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: AppColors.guruPrimary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fitness_center,
              size: 80,
              color: AppColors.guruPrimary,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'WTF Guru Coaching',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your premium AI-native personal training platform. Chat with expert coaches, schedule real-time video calls, and achieve your physical goals.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSlide(List<User> trainers) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Your Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configure your fitness profile to get started.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          const Text(
            'Full Name',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Enter your name',
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Email Address',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              hintText: 'Enter your email',
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Choose Your Personal Trainer',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: trainers.length,
            itemBuilder: (context, index) {
              final trainer = trainers[index];
              final isSelected = _selectedTrainer?.id == trainer.id;
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTrainer = trainer;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? AppColors.guruPrimary.withOpacity(0.05) 
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      color: isSelected ? AppColors.guruPrimary : AppColors.border,
                      width: isSelected ? 2.0 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: NetworkImage(trainer.avatarUrl ?? ''),
                        radius: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trainer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              trainer.email,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.guruPrimary,
                        )
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Slide indicators
          Row(
            children: [
              _buildIndicator(0),
              const SizedBox(width: 8),
              _buildIndicator(1),
            ],
          ),
          
          // Action button
          ElevatedButton(
            onPressed: () async {
              if (_currentPage == 0) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              } else {
                // Save and complete onboarding
                if (_nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter your name.')),
                  );
                  return;
                }

                final auth = ref.read(authServiceProvider);
                final assignedTrainer = _selectedTrainer ?? auth.getSeededTrainers().first;
                
                final memberUser = User(
                  id: 'dk_member',
                  role: UserRole.member,
                  name: _nameController.text.trim(),
                  email: _emailController.text.trim(),
                  avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80',
                  assignedTrainerId: assignedTrainer.id,
                );

                await auth.setCurrentUser(memberUser);
                await auth.setOnboardingCompleted(true);
                
                // Trigger sync service to read the updated current user
                ref.read(currentUserProvider.notifier).state = memberUser;
                
                // Start sync loop
                ref.read(syncServiceProvider).startSyncLoop();

                if (mounted) {
                  context.go('/');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.guruPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: Text(_currentPage == 0 ? 'Next' : 'Get Started'),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(int index) {
    final active = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.guruPrimary : AppColors.border,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
