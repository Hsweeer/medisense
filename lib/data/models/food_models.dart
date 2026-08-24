enum DietaryStatus { halal, haram, unknown }

class FoodNutrition {
  const FoodNutrition({
    required this.calories,
    required this.carbsG,
    required this.fatG,
    required this.proteinG,
    required this.dietaryStatus,
    required this.portionLabel,
  });

  final double calories;
  final double carbsG;
  final double fatG;
  final double proteinG;
  final DietaryStatus dietaryStatus;
  final String portionLabel;

  FoodNutrition scaledBy(double factor) => FoodNutrition(
        calories: calories * factor,
        carbsG: carbsG * factor,
        fatG: fatG * factor,
        proteinG: proteinG * factor,
        dietaryStatus: dietaryStatus,
        portionLabel: portionLabel,
      );
}

class FoodLogEntry {
  const FoodLogEntry({
    this.id,
    required this.foodName,
    required this.nutrition,
    required this.insightNote,
    required this.loggedAt,
    this.photoUrl,
  });

  final String? id;
  final String foodName;
  final FoodNutrition nutrition;
  final String insightNote;
  final DateTime loggedAt;
  final String? photoUrl;

  Map<String, dynamic> toMap() => {
        'foodName': foodName,
        'calories': nutrition.calories,
        'carbsG': nutrition.carbsG,
        'fatG': nutrition.fatG,
        'proteinG': nutrition.proteinG,
        'dietaryStatus': nutrition.dietaryStatus.name,
        'portionLabel': nutrition.portionLabel,
        'insightNote': insightNote,
        'loggedAtMs': loggedAt.millisecondsSinceEpoch,
        'photoUrl': photoUrl,
      };

  factory FoodLogEntry.fromMap(Map<String, dynamic> map, String id) => FoodLogEntry(
        id: id,
        foodName: map['foodName'] ?? '',
        nutrition: FoodNutrition(
          calories: (map['calories'] as num?)?.toDouble() ?? 0,
          carbsG: (map['carbsG'] as num?)?.toDouble() ?? 0,
          fatG: (map['fatG'] as num?)?.toDouble() ?? 0,
          proteinG: (map['proteinG'] as num?)?.toDouble() ?? 0,
          dietaryStatus: DietaryStatus.values.firstWhere(
            (e) => e.name == map['dietaryStatus'],
            orElse: () => DietaryStatus.unknown,
          ),
          portionLabel: map['portionLabel'] ?? '',
        ),
        insightNote: map['insightNote'] ?? '',
        loggedAt: map['loggedAtMs'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['loggedAtMs'])
            : DateTime.now(),
        photoUrl: map['photoUrl'],
      );
}