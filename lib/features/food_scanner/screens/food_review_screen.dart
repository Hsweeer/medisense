import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/food_insight_service.dart';
import '../../../core/services/food_log_service.dart';
import '../../../core/services/nutrition_history_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/guest_gate.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../data/models/food_models.dart';
import '../../../data/models/models.dart';

class FoodReviewScreen extends StatefulWidget {
  const FoodReviewScreen({
    super.key,
    required this.foodName,
    required this.portionLabel,
    required this.nutrition,
    this.ingredients,
    this.photo,
    this.photoBytes,
  });

  final String foodName;
  final String portionLabel;
  final FoodNutrition nutrition;
  final String? ingredients;
  final File? photo;
  final Uint8List? photoBytes;

  @override
  State<FoodReviewScreen> createState() => _FoodReviewScreenState();
}

class _FoodReviewScreenState extends State<FoodReviewScreen> {
  double _portionMultiplier = 1.0;
  String? _insight;
  bool _loadingInsight = true;
  bool _saving = false;

  FoodNutrition get _adjusted => widget.nutrition.scaledBy(_portionMultiplier);

  /// Calorie-weighted share of each macronutrient (protein/carbs = 4 kcal
  /// per gram, fat = 9 kcal per gram) — the standard way nutrition labels
  /// express "% of calories from X", so the numbers read as exact rather
  /// than a rough gram ratio.
  ({double protein, double carbs, double fat}) get _macroPercent {
    final n = _adjusted;
    final proteinKcal = n.proteinG * 4;
    final carbsKcal = n.carbsG * 4;
    final fatKcal = n.fatG * 9;
    final total = proteinKcal + carbsKcal + fatKcal;
    if (total <= 0) return (protein: 0, carbs: 0, fat: 0);
    return (
      protein: proteinKcal / total,
      carbs: carbsKcal / total,
      fat: fatKcal / total,
    );
  }

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
    final historyEnabled = await NutritionHistoryPreferences.instance
        .isEnabled();
    if (!mounted) return;
    if (historyEnabled &&
        !await requireLogin(
          context,
          feature: 'save this to your nutrition history',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);

    if (historyEnabled) {
      await FoodLogService.instance.save(
        FoodLogEntry(
          foodName: widget.foodName,
          nutrition: _adjusted,
          insightNote: _insight ?? '',
          loggedAt: DateTime.now(),
          photoUrl: null,
        ),
      );
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  ({Color fg, Color bg, IconData icon, String label}) _statusStyle(
    DietaryStatus status,
  ) {
    switch (status) {
      case DietaryStatus.halal:
        return (
          fg: AppColors.success,
          bg: AppColors.successSoft,
          icon: Icons.check_circle_rounded,
          label: 'Halal',
        );
      case DietaryStatus.haram:
        return (
          fg: AppColors.danger,
          bg: AppColors.dangerSoft,
          icon: Icons.cancel_rounded,
          label: 'Not halal',
        );
      case DietaryStatus.unknown:
        return (
          fg: AppColors.muted,
          bg: AppColors.paper,
          icon: Icons.help_rounded,
          label: 'Unverified',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _adjusted;
    final status = _statusStyle(n.dietaryStatus);
    final hasPhoto = widget.photoBytes != null || widget.photo != null;

    return Scaffold(
      backgroundColor: AppColors.paper,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 6),
          child: _CircleIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Hero photo with soft bottom fade so the sheet below reads as
          // one continuous surface, not two stacked rectangles.
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                child: hasPhoto
                    ? (widget.photoBytes != null
                          ? Image.memory(
                              widget.photoBytes!,
                              height: 260,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              widget.photo!,
                              height: 260,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ))
                    : Container(
                        height: 220,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: AppColors.gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.restaurant_rounded,
                            color: Colors.white,
                            size: 56,
                          ),
                        ),
                      ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: .32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Content sheet — pulled up over the photo for a layered look.
          Transform.translate(
            offset: const Offset(0, -22),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              decoration: const BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row + dietary status chip
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.foodName,
                          style: GoogleFonts.sora(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.15,
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: status.bg,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(status.icon, size: 15, color: status.fg),
                            const SizedBox(width: 5),
                            Text(
                              status.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: status.fg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.straighten_rounded,
                        size: 14,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.portionLabel,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (n.isEstimated) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warningSoft,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'Estimated',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Portion adjuster
                  MCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Portion',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.soft,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '${(_portionMultiplier * 100).round()}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: AppColors.line,
                            thumbColor: AppColors.primary,
                            overlayColor: AppColors.primary.withValues(
                              alpha: .12,
                            ),
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: _portionMultiplier,
                            min: 0.25,
                            max: 2.5,
                            divisions: 9,
                            onChanged: (v) =>
                                setState(() => _portionMultiplier = v),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Calories highlight
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: AppColors.gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: .28),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.local_fire_department_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CALORIES',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .82),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text.rich(
                                TextSpan(
                                  text: n.calories.toStringAsFixed(0),
                                  style: GoogleFonts.sora(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  children: const [
                                    TextSpan(
                                      text: '  kcal',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Macro grid — quick glance
                  Row(
                    children: [
                      Expanded(
                        child: _MacroTile(
                          icon: Icons.fitness_center_rounded,
                          label: 'Protein',
                          value: '${n.proteinG.toStringAsFixed(0)}g',
                          color: AppColors.primary,
                          background: AppColors.soft,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MacroTile(
                          icon: Icons.grain_rounded,
                          label: 'Carbs',
                          value: '${n.carbsG.toStringAsFixed(0)}g',
                          color: AppColors.warning,
                          background: AppColors.warningSoft,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MacroTile(
                          icon: Icons.opacity_rounded,
                          label: 'Fat',
                          value: '${n.fatG.toStringAsFixed(0)}g',
                          color: AppColors.ai,
                          background: AppColors.aiSoft,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // Nutrition facts — exact per-macro breakdown with
                  // calorie-weighted percentages, echoing a real label.
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Nutrition facts',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Column(
                      children: [
                        _NutritionFactRow(
                          icon: Icons.fitness_center_rounded,
                          label: 'Protein',
                          grams: n.proteinG,
                          percent: _macroPercent.protein,
                          color: AppColors.primary,
                        ),
                        Divider(height: 22, color: AppColors.line),
                        _NutritionFactRow(
                          icon: Icons.grain_rounded,
                          label: 'Carbohydrates',
                          grams: n.carbsG,
                          percent: _macroPercent.carbs,
                          color: AppColors.warning,
                        ),
                        Divider(height: 22, color: AppColors.line),
                        _NutritionFactRow(
                          icon: Icons.opacity_rounded,
                          label: 'Fat',
                          grams: n.fatG,
                          percent: _macroPercent.fat,
                          color: AppColors.ai,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  Row(
                    children: [
                      Icon(
                        Icons.list_alt_rounded,
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Ingredients',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MCard(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.ingredients?.trim().isNotEmpty == true
                          ? widget.ingredients!.trim()
                          : 'Ingredients are not available for this product.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // AI insight
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: AppColors.ai,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'AI insight',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MCard(
                    color: AppColors.aiSoft,
                    border: Border.all(
                      color: AppColors.ai.withValues(alpha: .22),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: _loadingInsight
                        ? const AppInlineProgressRow(
                            label: 'Generating insight…',
                            color: AppColors.ai,
                          )
                        : Text(
                            (_insight == null || _insight!.isEmpty)
                                ? 'Could not generate a personalized note right now.'
                                : _insight!,
                            style: const TextStyle(
                              fontSize: 12.8,
                              height: 1.45,
                              color: AppColors.inkSoft,
                            ),
                          ),
                  ),

                  const SizedBox(height: 10),
                  Text(
                    'This information is for general guidance and is not a '
                    'substitute for professional medical advice.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
                  ),

                  const SizedBox(height: 26),

                  // Confirm & save
                  _SaveButton(saving: _saving, onPressed: _confirm),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionFactRow extends StatelessWidget {
  const _NutritionFactRow({
    required this.icon,
    required this.label,
    required this.grams,
    required this.percent,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double grams;
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              '${grams.toStringAsFixed(1)}g',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${(percent * 100).toStringAsFixed(1)}%)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: percent.clamp(0, 1),
            minHeight: 5,
            backgroundColor: AppColors.line,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return MCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Premium, on-brand "Confirm & save" action — a gradient pill button with
/// a built-in loading state, matching the app's primary CTA language
/// (see [PrimaryButton]) but supporting an inline spinner while saving.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: AppColors.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: .32),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: saving ? null : onPressed,
            child: Center(
              child: saving
                  ? const AppSpinner.inline(size: 20, color: Colors.white)
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Confirm & save',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .32),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
