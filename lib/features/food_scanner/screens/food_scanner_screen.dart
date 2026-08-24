import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/food_vision_service.dart';
import '../../../core/services/open_food_facts_service.dart';
import 'food_review_screen.dart';

class FoodScannerScreen extends StatefulWidget {
  const FoodScannerScreen({super.key});

  @override
  State<FoodScannerScreen> createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends State<FoodScannerScreen> {
  bool _processing = false;

  Future<void> _capture(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _processing = true);
    final photo = File(picked.path);

    final identification = await FoodVisionService.instance.identify(photo);

    if (identification == null || !identification.confident) {
      if (!mounted) return;
      setState(() => _processing = false);
      _goToManualSearch();
      return;
    }

    final nutrition = await OpenFoodFactsService.instance.lookup(
      identification.foodName,
    );

    if (!mounted) return;
    setState(() => _processing = false);

    if (nutrition == null) {
      _goToManualSearch(prefill: identification.foodName);
      return;
    }

    Navigator.push(
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
  }

  void _goToManualSearch({String? prefill}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not confidently identify this food${prefill != null ? " ($prefill?)" : ""} — search manually.',
        ),
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
                  Text('Identifying and verifying...'),
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
