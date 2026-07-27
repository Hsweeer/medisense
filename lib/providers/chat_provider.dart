import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/models.dart';
import 'reminder_provider.dart';

/// MedAI — the in-app health assistant.
///
/// Frontend-only: replies are scripted locally. The provider still models the
/// full product surface — image / file / voice attachments, a red-flag → SOS
/// escalation, and "Personal insights" (replies tailored from the user's
/// health profile — the hook where on-device / backend training plugs in).
class ChatProvider extends ChangeNotifier {
  ChatProvider({this.reminderEngine}) {
    messages.add(const ChatMessage(
      role: ChatRole.ai,
      text:
          "Hi Emily, I'm MedAI — your personal health assistant. I can answer "
          "health questions, read lab reports or photos you upload, and listen "
          "to voice notes. I've learned your health profile, so my guidance "
          "accounts for your penicillin and peanut allergies and mild asthma."
          "\n\nHow are you feeling today?",
      personalized: true,
    ));
  }

  /// Lets MedAI create alarms itself after scanning a prescription.
  final ReminderProvider? reminderEngine;

  final messages = <ChatMessage>[];
  bool typing = false;

  /// "Personal insights" — tailor replies from the health profile.
  bool learnFromData = true;

  /// Attachments staged in the composer, sent with the next message.
  final pendingAttachments = <ChatAttachment>[];

  bool recording = false;
  Timer? _timer;

  void toggleLearn() {
    learnFromData = !learnFromData;
    notifyListeners();
  }

  void stageAttachment(ChatAttachment attachment) {
    pendingAttachments.add(attachment);
    notifyListeners();
  }

  void removeStaged(ChatAttachment attachment) {
    pendingAttachments.remove(attachment);
    notifyListeners();
  }

  void startRecording() {
    recording = true;
    notifyListeners();
  }

  /// Ends the hold-to-talk gesture; sends a voice message when long enough.
  void stopRecording({required int seconds, bool cancelled = false}) {
    recording = false;
    if (!cancelled && seconds >= 1) {
      _sendUser(
        '',
        [
          ChatAttachment(
              type: AttachmentType.voice,
              name: 'Voice note',
              detail: '0:${seconds.toString().padLeft(2, '0')}',
              durationSeconds: seconds),
        ],
      );
      _reply(_voiceReply());
    }
    notifyListeners();
  }

  void send(String text) {
    final t = text.trim();
    if (t.isEmpty && pendingAttachments.isEmpty) return;
    final attachments = [...pendingAttachments];
    pendingAttachments.clear();
    _sendUser(t, attachments);
    _reply(_composeReply(t, attachments));
  }

  void _sendUser(String text, List<ChatAttachment> attachments) {
    messages.add(ChatMessage(
        role: ChatRole.user, text: text, attachments: attachments));
    notifyListeners();
  }

  void _reply(ChatMessage message) {
    typing = true;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1400), () {
      typing = false;
      messages.add(message);
      notifyListeners();
    });
  }

  static const _redFlags = [
    'chest pain',
    "can't breathe",
    'cannot breathe',
    'severe bleeding',
    'stroke',
    'unconscious',
    'suicide',
    'overdose',
  ];

  ChatMessage _composeReply(String text, List<ChatAttachment> attachments) {
    final lower = text.toLowerCase();

    if (_redFlags.any(lower.contains)) {
      return const ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.sos,
        text:
            'Symptoms like these can be serious. Please call 911 or use '
            'Emergency SOS now — I can alert your emergency contacts too.',
      );
    }

    // Prescription scan — parse the doctor's note, flag allergy conflicts,
    // and add the safe medications as alarm reminders automatically.
    if (attachments.any((a) => a.intent == AttachmentIntent.prescription)) {
      reminderEngine?.addAll([
        Reminder(
            title: 'Ibuprofen',
            dose: '400 mg · 1 tablet',
            time: '8:00 AM & 8:00 PM',
            schedule: 'Daily · 5 days',
            instructions: 'After food',
            addedBy: 'MedAI'),
        Reminder(
            title: 'Cetirizine',
            dose: '10 mg · 1 tablet',
            time: '9:00 PM',
            schedule: 'Nightly · 7 days',
            instructions: 'May cause drowsiness',
            addedBy: 'MedAI'),
      ]);
      return ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.prescription,
        personalized: learnFromData,
        text:
            "I've read Dr. Nguyen's note. It prescribes:\n\n"
            '• Ibuprofen 400 mg — twice daily after food, 5 days\n'
            '• Cetirizine 10 mg — nightly, 7 days\n'
            '• Amoxicillin 500 mg — 3× daily, 7 days'
            "${learnFromData ? '\n\n⚠ Heads-up: Amoxicillin is a '
                'penicillin-class antibiotic and your profile lists a '
                'penicillin allergy. I have NOT set reminders for it — '
                'please confirm with your doctor before taking it.' : ''}"
            '\n\nI added alarm reminders for the other two — you can '
            'snooze, edit, or delete them anytime in Reminders.',
      );
    }

    // Skin check — analyze the photo and suggest likely conditions.
    if (attachments.any((a) => a.intent == AttachmentIntent.skin)) {
      return ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.skin,
        personalized: learnFromData,
        text:
            'Most consistent with mild contact dermatitis: localized '
            'redness, slight dryness, no spreading edges, blistering, or '
            'discharge.'
            "${learnFromData ? '\n\nFor you: avoid antibiotic ointments '
                '(penicillin allergy) — fragrance-free moisturizer and a '
                'cool compress are safer first steps.' : ''}"
            '\n\nSee a clinician if it spreads, blisters, or you develop '
            'fever within 48 hours.',
      );
    }

    if (attachments.any((a) => a.type == AttachmentType.image)) {
      return ChatMessage(
        role: ChatRole.ai,
        personalized: learnFromData,
        text:
            "I've reviewed your photo. The area shows mild redness with no "
            "spreading edges or discharge — consistent with minor skin "
            "irritation. Keep it clean and dry, and avoid scratching."
            "${learnFromData ? '\n\nBecause of your penicillin allergy, skip '
                'antibiotic ointments like Neosporin unless your doctor okays '
                'one — plain petroleum jelly is a safe alternative.' : ''}"
            '\n\nIf it spreads, blisters, or you develop a fever, see a '
            'clinician within 24 hours.',
      );
    }

    if (attachments.any((a) => a.type == AttachmentType.file)) {
      return ChatMessage(
        role: ChatRole.ai,
        personalized: learnFromData,
        text:
            "I've read your document. Summary of key values:\n\n"
            '• Vitamin D: 24 ng/mL — slightly below the 30–100 range\n'
            '• Fasting glucose: 92 mg/dL — normal\n'
            '• Cholesterol (LDL): 96 mg/dL — optimal'
            "${learnFromData ? '\n\nGood news: the Vitamin D 2000 IU you '
                'already take is the usual fix — recheck levels in 3 months.' : ''}"
            '\n\nWant me to explain any value in plain English?',
      );
    }

    if (lower.contains('tired') || lower.contains('fatigue')) {
      return ChatMessage(
        role: ChatRole.ai,
        personalized: learnFromData,
        text:
            'Persistent tiredness usually traces back to sleep quality, '
            'hydration, iron or vitamin levels, or stress.'
            "${learnFromData ? ' Your last upload showed Vitamin D at '
                '24 ng/mL — low levels are a very common cause of fatigue, '
                'and your 2000 IU supplement should help within weeks.' : ''}"
            '\n\nTry a consistent sleep window this week; if it persists '
            'beyond 2–3 weeks, a basic blood panel is worth it.',
      );
    }

    if (lower.contains('headache')) {
      return ChatMessage(
        role: ChatRole.ai,
        personalized: learnFromData,
        text:
            'Most headaches are tension-type — hydration, screen breaks, and '
            'rest usually resolve them.'
            "${learnFromData ? ' For relief, acetaminophen (Tylenol) or '
                'ibuprofen are fine with your profile — no interactions with '
                'your current medications.' : ''}"
            '\n\nSeek urgent care if it is sudden and severe, follows a head '
            'injury, or comes with vision changes or a stiff neck.',
      );
    }

    if (lower.contains('cold') ||
        lower.contains('flu') ||
        lower.contains('medicine')) {
      return ChatMessage(
        role: ChatRole.ai,
        personalized: learnFromData,
        text:
            'For cold symptoms: rest, fluids, and OTC relief work for most '
            'people.'
            "${learnFromData ? '\n\nTailored to you: avoid combination '
                'products containing penicillin-class antibiotics (rare in '
                'OTC) and check labels for peanut-derived excipients. With '
                'mild asthma, skip mentholated vapor rubs if they trigger '
                'coughing — saline spray is safest.' : ''}"
            '\n\nWant me to find a 24-hour pharmacy nearby?',
      );
    }

    if (lower.contains('sleep')) {
      return const ChatMessage(
        role: ChatRole.ai,
        text:
            'A steady wind-down works better than any tracker: same bedtime '
            '±30 min, screens off 45 min before, bedroom below 68°F. Log it '
            'for a week and I can spot patterns with you.',
      );
    }

    return ChatMessage(
      role: ChatRole.ai,
      personalized: learnFromData,
      text:
          "Thanks — I've noted that in your health journal."
          "${learnFromData ? ' Everything you share here trains your personal '
              'model, so my answers keep getting more specific to you.' : ''}"
          '\n\nTell me more about your symptoms, or upload a photo, report, '
          'or voice note and I will take a look.',
    );
  }

  ChatMessage _voiceReply() {
    return ChatMessage(
      role: ChatRole.ai,
      personalized: learnFromData,
      text:
          "I listened to your voice note. I heard you mention throat "
          "discomfort since last night. Warm fluids and rest are the first "
          "line; most viral sore throats settle in 3–5 days."
          "${learnFromData ? '\n\nWith your mild asthma, watch for wheezing — '
              'if it starts, use your Albuterol inhaler as prescribed.' : ''}",
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
