# Developer Quick Start — Firestore Reminders

## 🚀 Getting Started (5 minutes)

### 1. Set Up Firestore (Firebase Console)

```firestore
match /users/{uid}/reminders/{reminderId} {
  allow read, write: if request.auth.uid == uid;
}
```

### 2. Start App

```bash
flutter run
```

### 3. Create First Reminder

1. Log in or sign up
2. Go to Reminders screen
3. Tap "Add reminder" button
4. Fill in details, tap "Save reminder"
5. Check Firestore console to confirm it was saved

### 4. Test Alarm

1. Create a reminder with time **2 minutes from now**
2. Wait 2 minutes
3. Notification should appear (even if app is closed)

---

## 🔍 Understanding the Code

### Reminder Creation Flow

```dart
// User taps "Save reminder" in modal
final reminder = Reminder(
  title: 'Ibuprofen',
  dose: '200 mg',
  time: '8:00 AM',
  schedule: 'Daily',
);

// Provider method (awaited in UI)
await reminderProvider.add(reminder);
```

**Behind the scenes:**

```
ReminderProvider.add()
  ↓
ReminderFirestoreService.createReminder()
  ├─ Create doc in Firestore: users/{uid}/reminders/{id}
  └─ Return reminder with assigned .id
  ↓
NotificationService.scheduleReminder(reminder)
  ├─ Parse time: "8:00 AM" → TimeOfDay(8, 0)
  ├─ Calculate next instance (tomorrow if past today)
  ├─ Create unique alarm ID from title hash
  ├─ Schedule native alarm at that time
  └─ For weekday schedule: create 5 alarms (Mon-Fri)
```

**Result:** Reminder appears in list, alarm fires at specified time tomorrow

---

## 💾 Working with Firestore

### Read Reminders

```dart
// Automatic on app startup (via ReminderProvider._initializeReminders)
final reminders = await firestoreService.fetchReminders();
```

Firestore query:
```javascript
users/{uid}/reminders (all documents)
```

### Create Reminder

```dart
final reminder = Reminder(...);
final saved = await firestoreService.createReminder(reminder);
print(saved?.id); // Firestore document ID
```

Firestore operation:
```javascript
users/{uid}/reminders.add({...})
```

### Update Reminder

```dart
reminder.time = '9:00 AM';
await firestoreService.updateReminder(reminder);
```

Firestore operation:
```javascript
users/{uid}/reminders/{id}.update({time: '9:00 AM'})
```

### Delete Reminder

```dart
await firestoreService.deleteReminder(reminder.id);
```

Firestore operation:
```javascript
users/{uid}/reminders/{id}.delete()
```

---

## 🔔 Alarm Scheduling

### Alarm ID Generation

```dart
// Title is the key - it's immutable and unique per reminder
int baseId = (title.hashCode.abs() % 100000) * 10;

// Examples:
"Ibuprofen" → 45670
"Vitamin D" → 78230
```

### Daily Schedule

```dart
schedule: 'Daily'
```

- One alarm per day
- Alarm ID: `baseId` (e.g., 45670)
- Repeats with `matchDateTimeComponents.time`
- Fires every day at the specified time

### Weekday Schedule

```dart
schedule: 'Weekdays'  // Mon-Fri
schedule: 'Mon · Wed · Fri'
```

- Multiple alarms (one per day)
- Alarm IDs: `baseId + weekday` (e.g., 45671 for Monday, 45672 for Tuesday)
- Each has own repeat rule: `matchDateTimeComponents.dayOfWeekAndTime`
- Fires only on selected days at the specified time

### Cancellation

```dart
// Before rescheduling or deleting
await NotificationService.instance.cancelForReminder(reminder);
```

This cancels:
- Daily alarm: `baseId`
- All weekday alarms: `baseId + 1` through `baseId + 7`

---

## 🧪 Testing

### Manual Test: Create & Fire Alarm

```dart
// 1. Create reminder with time 2 min from now
final now = DateTime.now();
final futureTime = now.add(Duration(minutes: 2));
final timeStr = '${futureTime.hour % 12}:${futureTime.minute.toString().padLeft(2, '0')} ${futureTime.hour >= 12 ? 'PM' : 'AM'}';

final reminder = Reminder(
  title: 'Test Alarm',
  dose: '1 test',
  time: timeStr,
  schedule: 'Daily',
);

await reminderProvider.add(reminder);

// 2. Wait 2 minutes
// 3. Notification should appear

// 4. Tap notification or wait for it to appear
// 5. Check notification history (Notifications screen)
```

### Automated Test: Firestore Persistence

```dart
// Create reminder
final reminder = Reminder(...);
final saved = await reminderProvider.add(reminder);

// Verify in Firestore
final firestore = FirebaseFirestore.instance;
final doc = await firestore
    .collection('users')
    .doc(uid)
    .collection('reminders')
    .doc(saved.id)
    .get();

expect(doc.exists, true);
expect(doc.data()?['title'], 'Test Reminder');
```

---

## 🐛 Debugging Tips

### Check if Reminder Saved to Firestore

1. Go to Firebase Console → Firestore
2. Click "users" collection
3. Find your user ID (copy from Firebase Auth console)
4. Open that document
5. Look for "reminders" subcollection
6. Should see your reminder documents

### Check if Alarm Scheduled

1. Create a reminder with time 1 minute from now
2. Check device system logs:
   ```bash
   adb logcat | grep -i notification
   ```
3. Look for `[NotificationService]` debug messages

### Check Notification History

1. Go to Notifications screen
2. Should see tapped notifications listed
3. If empty, no notifications have been tapped yet

### Force Reload Reminders

```dart
// Call in dev tools or somewhere in UI:
await reminderProvider.refresh();
```

This fetches all reminders from Firestore again.

---

## 📞 Common Issues

### "Reminders not loading"

**Checklist:**
- [ ] User is logged in (`AuthProvider.loggedIn == true`)
- [ ] Firestore security rules are set
- [ ] User has permission to read `users/{uid}/reminders`
- [ ] User's Firestore document exists (check console)

**Debug:**
```dart
final service = ReminderFirestoreService.instance;
print('User logged in: ${service.isLoggedIn}');
final reminders = await service.fetchReminders();
print('Loaded ${reminders.length} reminders');
```

### "Alarm not firing"

**Checklist:**
- [ ] Reminder shows in list with green status
- [ ] Time is in HH:MM AM/PM format
- [ ] Device notifications are enabled for the app
- [ ] Battery saver isn't blocking alarms
- [ ] Device has internet (for Firestore, but alarms work offline)

**Debug:**
```dart
// Check if reminder is enabled
print('Reminder enabled: ${reminder.enabled}');

// Check time parsing
final time = '8:00 AM';
// If valid: TimeOfDay(8, 0)
// If invalid: null (not scheduled)
```

### "Duplicate alarms"

**Should never happen**, but if it does:
1. Force close and restart app
2. This triggers `_initializeReminders()` which deduplicates

If duplicates persist:
1. Check alarm IDs in logs
2. Delete reminder and recreate
3. Report as bug

---

## 🎯 Common Tasks

### Add UI to Show Alarm Status

```dart
// In RemindersScreen, for each reminder card:
Icon(
  reminder.enabled ? Icons.check_circle : Icons.cancel,
  color: reminder.enabled ? Colors.green : Colors.red,
)
```

### Add Delete Confirmation

```dart
// In _showEditSheet(), before delete:
showDialog(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Delete reminder?'),
    content: const Text('This cannot be undone'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      TextButton(
        onPressed: () {
          prov.remove(reminder);
          Navigator.pop(ctx); // close dialog
          Navigator.pop(sheetCtx); // close modal
        },
        child: const Text('Delete', style: TextStyle(color: Colors.red)),
      ),
    ],
  ),
);
```

### Show Loading State

```dart
// In RemindersScreen:
if (prov.isLoading) {
  return const Center(child: CircularProgressIndicator());
}
// ... rest of UI
```

### Sync Reminders in Real-Time

```dart
// In ReminderProvider (future enhancement):
void _subscribeToUpdates() {
  _firestoreService.remindersStream().listen((updated) {
    reminders.clear();
    reminders.addAll(updated);
    notifyListeners();
  });
}
```

---

## 📚 File Reference

| File | Purpose | Key Methods |
|------|---------|-------------|
| `reminder_firestore_service.dart` | Firestore ops | `fetchReminders()`, `createReminder()`, `updateReminder()`, `deleteReminder()` |
| `reminder_provider.dart` | State + alarms | `add()`, `update()`, `remove()`, `enable()`, `disable()`, `take()`, `snooze()`, `skip()` |
| `models.dart` | Data model | `Reminder.fromMap()`, `Reminder.toMap()` |
| `reminders_screen.dart` | UI | `_showEditSheet()`, `_buildEmptyState()` |
| `notification_service.dart` | Native alarms | `scheduleReminder()`, `cancelForReminder()` |

---

## 🚢 Deployment Checklist

- [ ] Set Firestore security rules
- [ ] Test on Android device
- [ ] Test on iOS device
- [ ] Verify alarms fire at correct times
- [ ] Check notification history works
- [ ] Test offline reminders
- [ ] Test with 50+ reminders
- [ ] Monitor Firestore usage
- [ ] Deploy to production

---

## 📖 Read More

For complete details, see:
- `QUICK_REFERENCE.md` — API cheat sheet
- `REMINDERS_DOCUMENTATION.md` — Architecture & troubleshooting
- `FIRESTORE_SCHEMA.md` — Firestore setup & queries
- `IMPLEMENTATION_SUMMARY.md` — What was built

---

**Status**: ✅ Ready to code, test, and deploy
