import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

class ScheduleCallScreen extends ConsumerStatefulWidget {
  const ScheduleCallScreen({super.key});

  @override
  ConsumerState<ScheduleCallScreen> createState() => _ScheduleCallScreenState();
}

class _ScheduleCallScreenState extends ConsumerState<ScheduleCallScreen> {
  final TextEditingController _noteController = TextEditingController();
  
  late List<DateTime> _days;
  late DateTime _selectedDay;
  
  // Available time slots (hour, minute)
  final List<TimeOfDay> _slots = const [
    TimeOfDay(hour: 9, minute: 0),
    TimeOfDay(hour: 9, minute: 30),
    TimeOfDay(hour: 10, minute: 0),
    TimeOfDay(hour: 10, minute: 30),
    TimeOfDay(hour: 11, minute: 0),
    TimeOfDay(hour: 14, minute: 0),
    TimeOfDay(hour: 15, minute: 0),
    TimeOfDay(hour: 16, minute: 0),
    TimeOfDay(hour: 17, minute: 0),
    TimeOfDay(hour: 18, minute: 0), // 6:00 PM
  ];
  
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    // Generate next 3 days starting today
    final now = DateTime.now();
    _days = List.generate(3, (index) => DateTime(now.year, now.month, now.day).add(Duration(days: index)));
    _selectedDay = _days.first;
    _selectedTime = _slots.first;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  DateTime _getTargetDateTime(TimeOfDay slot) {
    return DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      slot.hour,
      slot.minute,
    );
  }

  Future<void> _submitRequest() async {
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a time slot.')),
      );
      return;
    }

    final targetDateTime = _getTargetDateTime(_selectedTime!);
    
    // Validation: Cannot pick past
    if (targetDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot book a slot in the past.')),
      );
      return;
    }

    final note = _noteController.text.trim();
    if (note.length > 140) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note must be less than 140 characters.')),
      );
      return;
    }

    try {
      await ref.read(callServiceProvider).requestCall(targetDateTime, note);
      
      if (mounted) {
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call requested. Waiting for trainer approval.'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop(); // Return to dashboard
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
            action: SnackBarAction(
              label: 'Copy',
              textColor: Colors.white,
              onPressed: () {
                // Action
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final approvedRequests = ref.watch(callRequestsProvider).where((r) => r.status == CallRequestStatus.approved);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule a Call'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Day selector
            const Text(
              'Select Date',
              style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Row(
              children: _days.map((day) {
                final isSelected = DateUtils.isSameDay(_selectedDay, day);
                final dayName = DateFormat('E').format(day);
                final dateStr = DateFormat('MMM d').format(day);
                
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDay = day;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4.0),
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.guruPrimary : AppColors.surface,
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: isSelected ? AppColors.guruPrimary : AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Text(
                            dayName,
                            style: TextStyle(
                              fontSize: 12.0, 
                              fontWeight: FontWeight.w600, 
                              color: isSelected ? Colors.white70 : AppColors.textSecondary
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 14.0, 
                              fontWeight: FontWeight.bold, 
                              color: isSelected ? Colors.white : AppColors.textPrimary
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // 2. Slots selector
            const Text(
              'Available Time Slots',
              style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.2,
              ),
              itemCount: _slots.length,
              itemBuilder: (context, index) {
                final slot = _slots[index];
                final isSelected = _selectedTime == slot;
                
                final targetDateTime = _getTargetDateTime(slot);
                final isPast = targetDateTime.isBefore(DateTime.now());
                
                // Conflict checking: does it conflict with any approved call request?
                final isBooked = approvedRequests.any((req) {
                  return req.scheduledFor.difference(targetDateTime).inMinutes.abs() < 30;
                });

                final timeStr = DateFormat('h:mm a').format(targetDateTime);
                
                Color bg = AppColors.surface;
                Color border = AppColors.border;
                Color text = AppColors.textPrimary;

                if (isPast || isBooked) {
                  bg = AppColors.background;
                  border = Colors.transparent;
                  text = AppColors.textMuted;
                } else if (isSelected) {
                  bg = AppColors.guruPrimary.withOpacity(0.1);
                  border = AppColors.guruPrimary;
                  text = AppColors.guruPrimary;
                }

                return GestureDetector(
                  onTap: (isPast || isBooked) ? null : () {
                    setState(() {
                      _selectedTime = slot;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(color: border, width: isSelected ? 1.5 : 1.0),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 13.0, 
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: text,
                          ),
                        ),
                        if (isBooked)
                          const Text(
                            'Booked',
                            style: TextStyle(fontSize: 8.0, color: AppColors.error, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // 3. Notes field
            const Text(
              'Add a Note (Optional)',
              style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLength: 140,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Describe what you want to cover in this session (e.g. Macros review)...',
                counterStyle: TextStyle(fontSize: 10.0),
              ),
            ),

            const SizedBox(height: 32),

            // 4. CTA
            ElevatedButton(
              onPressed: _submitRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.guruPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
              ),
              child: const Text('Request Call'),
            ),
          ],
        ),
      ),
    );
  }
}
