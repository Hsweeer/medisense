import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/food_vision_service.dart';
import '../../../core/services/open_food_facts_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../data/models/food_models.dart';
import 'food_review_screen.dart';
import 'food_scan_camera_screen.dart';

class FoodScannerScreen extends StatefulWidget {
  const FoodScannerScreen({super.key});

  @override
  State<FoodScannerScreen> createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends State<FoodScannerScreen> {
  bool _processing = false;

  Future<void> _capture(ImageSource source) async {
    if (_processing) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null) return;

    await _processPhoto(picked, source);
  }

  Future<void> _processPhoto(XFile picked, ImageSource source) async {
    if (_processing) return;
    setState(() => _processing = true);
    final photo = File(picked.path);
    final photoBytes = await picked.readAsBytes();
    try {
      final identification = await FoodVisionService.instance.identifyBytes(
        photoBytes,
      );
      FoodNutrition nutrition;
      try {
        final databaseNutrition = await OpenFoodFactsService.instance.lookup(
          identification.foodName,
        );
        nutrition = databaseNutrition == null
            ? await FoodVisionService.instance.estimateNutrition(identification)
            : _forDetectedPortion(databaseNutrition, identification);
      } on NutritionLookupException {
        nutrition = await FoodVisionService.instance.estimateNutrition(
          identification,
        );
      }

      if (!mounted) return;
      setState(() => _processing = false);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FoodReviewScreen(
            foodName: identification.foodName,
            portionLabel: identification.estimatedPortion,
            nutrition: nutrition,
            photo: photo,
            photoBytes: photoBytes,
          ),
        ),
      );
    } on FoodScanException catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      _showError(error.message, source);
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
      _showError(
        'Food analysis could not be completed. Please try again.',
        source,
      );
    }
  }

  FoodNutrition _forDetectedPortion(
    FoodNutrition nutrition,
    FoodIdentification food,
  ) {
    final weight = food.estimatedWeightGrams;
    final baseWeight = nutrition.portionWeightGrams;
    if (weight == null || baseWeight == null) return nutrition;
    return nutrition.scaledBy(weight / baseWeight);
  }

  Future<void> _showError(String message, ImageSource source) async {
    final shouldRetry = await AppDialog.confirm(
      context: context,
      title: 'Food scan unsuccessful',
      message: message,
      confirmText: 'Try again',
      cancelText: 'Choose another photo',
      icon: Icons.fastfood_rounded,
      accentColor: AppColors.warning,
    );

    if (!mounted) return;
    if (shouldRetry) {
      _capture(source);
    } else {
      _capture(ImageSource.gallery);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan food')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: SingleChildScrollView(
              child: _processing
                  ? const _AnalyzingState()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: AppColors.gradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.restaurant_menu_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Scan your food',
                          style: GoogleFonts.sora(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Snap a photo or pick one from your gallery and '
                          'MedAI will estimate calories, macros, and '
                          'dietary status in seconds.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 30),
                        PrimaryButton(
                          label: 'Take a photo',
                          icon: Icons.camera_alt_rounded,
                          onPressed: () async {
                            final photo = await Navigator.of(context)
                                .push<XFile>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const FoodScanCameraScreen(),
                                  ),
                                );
                            if (photo != null && mounted) {
                              _processPhoto(photo, ImageSource.camera);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'Choose from gallery',
                          icon: Icons.photo_library_rounded,
                          onPressed: () => _capture(ImageSource.gallery),
                        ),
                        const SizedBox(height: 26),
                        MCard(
                          color: AppColors.soft,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: .18),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.lightbulb_outline_rounded,
                                color: AppColors.primaryDark,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Good lighting and a clear, close-up angle '
                                  'help the AI recognize your food more '
                                  'accurately.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: AppColors.onSoft,
                                  ),
                                ),
                              ),
                            ],
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

/// Full-screen "analyzing" state shown while the captured photo is being
/// identified and looked up — a calmer, branded alternative to a bare
/// spinner + caption.
class _AnalyzingState extends StatelessWidget {
  const _AnalyzingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSpinner(size: 44),
        const SizedBox(height: 22),
        Text(
          'Analyzing your food…',
          style: GoogleFonts.sora(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'MedAI is identifying the food and estimating its nutrition.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      ],
    );
  }
}
