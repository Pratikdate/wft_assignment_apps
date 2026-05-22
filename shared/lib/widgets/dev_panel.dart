import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../utils/logger.dart';
import '../utils/theme.dart';

class DevPanelOverlay extends ConsumerWidget {
  const DevPanelOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      bottom: 80.0,
      right: 16.0,
      child: FloatingActionButton(
        mini: true,
        backgroundColor: AppColors.textPrimary.withOpacity(0.85),
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: () => showDevPanel(context),
        child: const Icon(Icons.more_vert, size: 20),
      ),
    );
  }

  static void showDevPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const DevPanelSheet(),
    );
  }
}

class DevPanelSheet extends ConsumerStatefulWidget {
  const DevPanelSheet({super.key});

  @override
  ConsumerState<DevPanelSheet> createState() => _DevPanelSheetState();
}

class _DevPanelSheetState extends ConsumerState<DevPanelSheet> {
  LogTag? _selectedFilter;

  @override
  Widget build(BuildContext context) {
    final syncService = ref.read(syncServiceProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12.0, bottom: 8.0),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'DevPanel Telemetry',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),

          const Divider(),

          // Env stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
              margin: EdgeInsets.zero,
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTelemetryRow('Sync Node URL', syncService.baseUrl),
                    _buildTelemetryRow('Active User', currentUser?.name ?? 'Guest'),
                    _buildTelemetryRow('Active Role', currentUser?.role.name.toUpperCase() ?? 'NONE'),
                    _buildTelemetryRow(
                      '100ms Secret', 
                      '******** (Masked)'
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Log section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Structured Logs (Live)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
                ),
                TextButton.icon(
                  onPressed: () {
                    final logText = AppLogger.logs.map((l) => l.toString()).join('\n');
                    Clipboard.setData(ClipboardData(text: logText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logs copied to clipboard')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy Logs'),
                )
              ],
            ),
          ),

          // Tag Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
            child: Row(
              children: [
                _buildFilterChip(null, 'ALL'),
                ...LogTag.values.map((tag) => _buildFilterChip(tag, tag.name)),
              ],
            ),
          ),

          // Logs Stream
          Expanded(
            child: StreamBuilder<List<LogEntry>>(
              stream: AppLogger.logsStream,
              initialData: AppLogger.logs,
              builder: (context, snapshot) {
                final allLogs = snapshot.data ?? [];
                final filteredLogs = _selectedFilter == null
                    ? allLogs
                    : allLogs.where((l) => l.tag == _selectedFilter).toList();

                if (filteredLogs.isEmpty) {
                  return const Center(
                    child: Text('No logs captured yet.', style: TextStyle(color: AppColors.textMuted)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: filteredLogs.length > 20 ? 20 : filteredLogs.length, // Display last 20
                  itemBuilder: (context, index) {
                    final entry = filteredLogs[index];
                    return _buildLogTile(entry);
                  },
                );
              },
            ),
          ),

          // Debug actions
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error.withOpacity(0.1),
                foregroundColor: AppColors.error,
              ),
              onPressed: () async {
                await Hive.deleteFromDisk();
                AppLogger.system('Local Hive caches purged');
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hive database purged. Please restart app.')),
                  );
                }
              },
              child: const Text('Purge Database & Reset'),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTelemetryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.0, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(LogTag? tag, String label) {
    final isSelected = _selectedFilter == tag;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12.0, color: isSelected ? Colors.white : AppColors.textSecondary)),
        selected: isSelected,
        selectedColor: AppColors.textPrimary,
        backgroundColor: AppColors.surface,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = selected ? tag : null;
          });
        },
      ),
    );
  }

  Widget _buildLogTile(LogEntry entry) {
    Color tagColor;
    switch (entry.tag) {
      case LogTag.CHAT:
        tagColor = AppColors.guruPrimary;
        break;
      case LogTag.RTC:
        tagColor = Colors.purple;
        break;
      case LogTag.SCHEDULE:
        tagColor = AppColors.warning;
        break;
      case LogTag.AUTH:
        tagColor = AppColors.success;
        break;
      case LogTag.SYSTEM:
        tagColor = AppColors.textSecondary;
        break;
    }

    final timeStr = '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: tagColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                  entry.tag.name,
                  style: TextStyle(color: tagColor, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                timeStr,
                style: const TextStyle(fontSize: 10.0, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.message,
            style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          ),
          if (entry.details != null) ...[
            const SizedBox(height: 2),
            Text(
              entry.details!,
              style: const TextStyle(fontSize: 11.0, fontFamily: 'monospace', color: AppColors.textSecondary),
            )
          ]
        ],
      ),
    );
  }
}
