import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/food_vision_service.dart';
import '../../../core/services/open_food_facts_service.dart';
import '../../../data/models/food_models.dart';
import 'food_review_screen.dart';

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

    setState(() => _processing = true);
    final photo = File(picked.path);
    try {
      final identification = await FoodVisionService.instance.identify(photo);
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

  void _showError(String message, ImageSource source) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Food scan unsuccessful'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _capture(ImageSource.gallery);
            },
            child: const Text('Choose another photo'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _capture(source);
            },
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan food')),
      body: Center(
        child: _processing
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Analyzing your food...'),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () => _capture(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Take a photo'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _capture(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Choose from gallery'),
                  ),
                ],
              ),
      ),
    );
  }
}
