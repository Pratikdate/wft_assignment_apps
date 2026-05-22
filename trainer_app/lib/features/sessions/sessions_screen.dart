import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(filteredSessionLogsProvider);
    final allLogs = ref.watch(sessionLogsProvider);
    final requests = ref.watch(callRequestsProvider);
    final activeFilter = ref.watch(activeLogFilterProvider);
    final logService = ref.read(logServiceProvider);

    final completedLogIds = allLogs.map((l) => l.id).toSet();
    final upcomingRequests = requests.where((r) => 
      r.status == CallRequestStatus.approved && 
      !completedLogIds.contains(r.id)
    ).toList();
    // Sort upcoming chronologically (earliest scheduled first)
    upcomingRequests.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trainer Session Logs'),
          bottom: const TabBar(
            indicatorColor: AppColors.trainerPrimary,
            labelColor: AppColors.trainerPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(text: 'Upcoming Sessions'),
              Tab(text: 'Session History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Upcoming Sessions
            _buildUpcomingTab(context, upcomingRequests),
            
            // Tab 2: Session History
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Filter Chips
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  color: AppColors.surface,
                  child: Row(
                    children: [
                      _buildFilterChip(ref, LogFilter.all, 'All', activeFilter),
                      const SizedBox(width: 8),
                      _buildFilterChip(ref, LogFilter.last7Days, 'Last 7 Days', activeFilter),
                      const SizedBox(width: 8),
                      _buildFilterChip(ref, LogFilter.thisMonth, 'This Month', activeFilter),
                    ],
                  ),
                ),
                
                const Divider(height: 1),

                // Logs List
                Expanded(
                  child: logs.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            return _buildSessionLogCard(context, log, logService, ref);
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(WidgetRef ref, LogFilter filter, String label, LogFilter currentFilter) {
    final isSelected = filter == currentFilter;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.bold)),
      selected: isSelected,
      selectedColor: AppColors.trainerPrimary,
      backgroundColor: AppColors.background,
      onSelected: (_) {
        ref.read(activeLogFilterProvider.notifier).state = filter;
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_outlined, size: 64, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            'No workout session logs found.',
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 16.0),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionLogCard(BuildContext context, SessionLog log, LogService logService, WidgetRef ref) {
    final dateStr = DateFormat('EEEE, MMMM d, y').format(log.startedAt);
    final durationMin = log.durationSec ~/ 60;
    final durationSec = log.durationSec % 60;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.0),
        onTap: () => _showSessionDetails(context, log, ref),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 18, color: AppColors.trainerPrimary),
                    onPressed: () {
                      final summary = logService.generateExportText(log);
                      Clipboard.setData(ClipboardData(text: summary));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Session log summary copied to clipboard!')),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${durationMin}m ${durationSec}s',
                    style: const TextStyle(fontSize: 13.0, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 16),
                  
                  // Rating display
                  if (log.rating != null) ...[
                    const Icon(Icons.star, size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '${log.rating} Stars (Member)',
                      style: const TextStyle(fontSize: 13.0, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                    ),
                  ] else ...[
                    const Icon(Icons.star_outline, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    const Text(
                      'Unrated',
                      style: TextStyle(fontSize: 13.0, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
              if (log.memberNotes != null || log.trainerNotes != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),
                Text(
                  log.trainerNotes ?? log.memberNotes ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.0, color: AppColors.textMuted),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  void _showSessionDetails(BuildContext context, SessionLog log, WidgetRef ref) {
    final dateStr = DateFormat('MMMM d, yyyy').format(log.startedAt);
    final notesController = TextEditingController(text: log.trainerNotes);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session Details (DK)', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(dateStr, style: const TextStyle(fontSize: 13.0, color: AppColors.textMuted)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('${log.durationSec ~/ 60} min ${log.durationSec % 60} sec'),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                
                // Member notes & rating
                const Text('Member Notes & Rating', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0)),
                const SizedBox(height: 4),
                if (log.rating != null) ...[
                  Row(
                    children: List.generate(5, (index) => Icon(
                      index < log.rating! ? Icons.star : Icons.star_border,
                      color: AppColors.warning,
                      size: 20,
                    )),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  log.memberNotes ?? 'No feedback or notes added by member.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                
                const SizedBox(height: 16),
                
                // Trainer Notes
                const Text('Trainer Feedback Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0)),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Add macro/workout adjustment notes for DK...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await ref.read(logServiceProvider).submitTrainerFeedback(log.id, notesController.text.trim());
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Trainer notes updated.'), backgroundColor: AppColors.success),
                );
              },
              child: const Text('Save Notes', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUpcomingTab(BuildContext context, List<CallRequest> upcoming) {
    if (upcoming.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined, size: 64, color: AppColors.textMuted.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'No upcoming sessions scheduled.',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 16.0),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: upcoming.length,
      itemBuilder: (context, index) {
        final req = upcoming[index];
        return _buildUpcomingCard(context, req);
      },
    );
  }

  Widget _buildUpcomingCard(BuildContext context, CallRequest req) {
    final dateStr = DateFormat('EEEE, MMMM d, y').format(req.scheduledFor);
    final timeStr = DateFormat('h:mm a').format(req.scheduledFor);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today, color: AppColors.trainerPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dateStr,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0, color: AppColors.textPrimary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.trainerPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    timeStr,
                    style: const TextStyle(color: AppColors.trainerPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Member: DK',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0, color: AppColors.textPrimary),
            ),
            if (req.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'Note from member:',
                style: TextStyle(fontSize: 11.0, color: AppColors.textMuted, fontWeight: FontWeight.bold),
              ),
              Text(
                req.note,
                style: const TextStyle(fontSize: 13.0, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                context.push('/call/${req.id}');
              },
              icon: const Icon(Icons.videocam, color: Colors.white),
              label: const Text('Join Call', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.trainerPrimary,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
