import 'package:flutter/foundation.dart';

import '../data/mock/mock_data.dart';
import '../data/models/models.dart';

/// Health profile + the user's emergency contacts (editable).
class ProfileProvider extends ChangeNotifier {
  HealthProfile profile = MockData.profile;

  final List<EmergencyContact> contacts = [...MockData.emergencyContacts];

  void addContact(EmergencyContact contact) {
    contacts.add(contact);
    notifyListeners();
  }

  void removeContact(EmergencyContact contact) {
    contacts.remove(contact);
    notifyListeners();
  }
}
