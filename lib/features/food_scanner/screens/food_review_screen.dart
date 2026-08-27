import 'dart:io';
import 'package:flutter/material.dart';

import '../../../core/services/food_insight_service.dart';
import '../../../core/services/food_log_service.dart';
import '../../../data/models/food_models.dart';
import '../../../data/models/models.dart';

class FoodReviewScreen extends StatefulWidget {
  const FoodReviewScreen({
    super.key,
    required this.foodName,
    required this.portionLabel,
    required this.nutrition,
    this.photo,
  });

  final String foodName;
  final String portionLabel;
  final FoodNutrition nutrition;
  final File? photo;

  @override
  State<FoodReviewScreen> createState() => _FoodReviewScreenState();
}

class _FoodReviewScreenState extends State<FoodReviewScreen> {
  double _portionMultiplier = 1.0;
  String? _insight;
  bool _loadingInsight = true;
  bool _saving = false;

  FoodNutrition get _adjusted => widget.nutrition.scaledBy(_portionMultiplier);

  @override
  void initState() {
    super.initState();
    _loadInsight();
  }

  Future<void> _loadInsight() async {
    // Replace with your app's real signed-in HealthProfile (e.g. via
    // context.read<ProfileProvider>().profile) instead of this stub.
    const profile = HealthProfile(
      name: '',
      dob: '',
      bloodType: '',
      heightIn: 0,
      weightLb: 0,
      allergies: [],
      conditions: [],
      medications: [],
    );

    final note = await FoodInsightService.instance.generateInsight(
      foodName: widget.foodName,
      nutrition: _adjusted,
      profile: profile,
    );

    if (!mounted) return;
    setState(() {
      _insight = note;
      _loadingInsight = false;
    });
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);

    await FoodLogService.instance.save(
      FoodLogEntry(
        foodName: widget.foodName,
        nutrition: _adjusted,
        insightNote: _insight ?? '',
        loggedAt: DateTime.now(),
        photoUrl: null,
      ),
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = _adjusted;
    return Scaffold(
      appBar: AppBar(title: Text(widget.foodName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(widget.photo!, height: 180, fit: BoxFit.cover),
            ),
          const SizedBox(height: 16),
          Text('Portion', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _portionMultiplier,
            min: 0.25,
            max: 2.5,
            divisions: 9,
            label: '${(_portionMultiplier * 100).round()}%',
            onChanged: (v) => setState(() => _portionMultiplier = v),
          ),
          const SizedBox(height: 8),
          _NutritionRow('Calories', '${n.calories.toStringAsFixed(0)} kcal'),
          _NutritionRow('Carbs', '${n.carbsG.toStringAsFixed(0)} g'),
          _NutritionRow('Fat', '${n.fatG.toStringAsFixed(0)} g'),
          _NutritionRow('Protein', '${n.proteinG.toStringAsFixed(0)} g'),
          _NutritionRow('Dietary status', n.dietaryStatus.name),
          if (n.isEstimated)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Estimated nutrition',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Insight', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          _loadingInsight
              ? const LinearProgressIndicator()
              : Text(
                  _insight ?? '',
                  style: const TextStyle(color: Colors.grey),
                ),
          const SizedBox(height: 8),
          const Text(
            'This information is for general guidance and is not a substitute '
            'for professional medical advice.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirm & save'),
          ),
        ],
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  const _NutritionRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
