import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/services/food_log_service.dart';
import '../../core/services/nutrition_history_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/food_models.dart';

class NutritionHistoryScreen extends StatefulWidget {
  const NutritionHistoryScreen({super.key});

  @override
  State<NutritionHistoryScreen> createState() => _NutritionHistoryScreenState();
}

class _NutritionHistoryScreenState extends State<NutritionHistoryScreen> {
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final enabled = await NutritionHistoryPreferences.instance.isEnabled();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _enabled = enabled);
    await NutritionHistoryPreferences.instance.setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nutrition')),
      body: ListView(
        padding: EdgeInsets.all(20.w),
        children: [
          Card(
            child: SwitchListTile.adaptive(
              value: _loading ? true : _enabled,
              onChanged: _loading ? null : _toggle,
              activeThumbColor: AppColors.primary,
              title: const Text('Save nutrition history'),
              subtitle: const Text(
                'Keep scanned meals and nutrition values in your account.',
              ),
            ),
          ),
          SizedBox(height: 20.h),
          if (!_enabled && !_loading)
            const Text('History saving is off. New scans will not be added.'),
          if (_enabled && !_loading)
            StreamBuilder<List<FoodLogEntry>>(
              stream: FoodLogService.instance.allEntries(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Could not load nutrition history.');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return const Text('No nutrition history yet.');
                }
                return Column(children: entries.map(_entryTile).toList());
              },
            ),
        ],
      ),
    );
  }

  Widget _entryTile(FoodLogEntry entry) {
    final nutrition = entry.nutrition;
    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      child: ListTile(
        title: Text(
          entry.foodName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${nutrition.portionLabel} · ${nutrition.calories.toStringAsFixed(0)} kcal\n${entry.loggedAt.toLocal()}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            nutrition.isEstimated
                ? const Chip(label: Text('Estimated'))
                : const Chip(label: Text('Database')),
            IconButton(
              tooltip: 'Delete nutrition entry',
              icon: const Icon(Icons.delete_outline_rounded),
              color: AppColors.danger,
              onPressed: () => _confirmDelete(entry),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(FoodLogEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete nutrition entry?'),
        content: Text('Remove ${entry.foodName} from your nutrition history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || entry.id == null || !mounted) return;
    try {
      await FoodLogService.instance.delete(entry.id!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this entry.')),
        );
      }
    }
  }
}
