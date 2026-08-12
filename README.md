# MediSense - Smart Care. Anywhere. 🏥✨

**MediSense** is a professional, high-availability health companion and emergency assistant app. It is designed to ensure patients never miss a dose, have immediate access to emergency services system-wide, and receive personalized health guidance through advanced AI.

---

## 🚀 Key Features

### 🚨 Critical SOS System (High Availability)
*   **Dual-Trigger Mechanism**: Activate SOS via the in-app dashboard or the system-wide **Floating Overlay Button**.
*   **Background Resilience**: Uses Native Android Broadcasts to ensure the SOS trigger works even if the app is fully terminated (Killed state).
*   **Android 14 Ready**: Implements **Full-Screen Intents** and `CATEGORY_CALL` notifications to bypass background restrictions and wake the device instantly.
*   **Instant Navigation**: Deep Linking (`medisense://sos`) ensures users land directly on the emergency dashboard from any state.

### 💊 Intelligent Medication Reminders
*   **Native Alarm Engine**: Offline-capable alarms that trigger a full-screen "ringing" activity, even if the phone is locked or on "Do Not Disturb".
*   **AI Voice Alerts**: High-quality TTS engine announces "It's your medicine time" during alarms.
*   **Adherence Analytics**: Real-time calculation of "Taken vs. Scheduled" doses with streak tracking and progress visualization.
*   **Cloud Synchronization**: All reminders are synced to Firebase Firestore based on **User ID**, allowing data recovery across devices.

### 🤖 MedAI - Your Health Assistant
*   **Prescription OCR**: Scan physical prescriptions using Tesseract OCR to automatically extract medicine names, dosages, and schedules.
*   **Personalized Chat**: Powered by LLMs (llama-3.3) and integrated with your health profile to provide advice that accounts for your specific allergies and conditions.
*   **Offline First**: Crucial scanning and health logging features work without an active internet connection.

### 📍 Nearby Care & Emergency Ride
*   **Hospital Locator**: Live map showing the nearest ER-equipped hospitals and pharmacies with real-time distance and ETA calculation.
*   **Emergency Ride Booking**: Simulated dispatch system for emergency transport with live driver tracking and Medical ID sharing for responders.

---

## 🛠 Technical Stack
*   **Frontend**: Flutter (Dart)
*   **Backend**: Firebase (Authentication, Firestore, Storage)
*   **Native (Android)**: Kotlin (Services, Broadcast Receivers, Window Manager, AlarmManager)
*   **AI/Vision**: Tesseract OCR, Groq LLM API
*   **State Management**: Provider (Architecture optimized for multi-engine communication)

---

## 📋 Essential Permissions
For the best experience, the app requires:
1.  **Notifications**: For critical medication and SOS alerts.
2.  **Display Over Other Apps**: For the floating SOS emergency button.
3.  **Ignore Battery Optimization**: To ensure alarms fire exactly on time.
4.  **Location**: To locate the nearest care facilities and provide tracking for SOS rides.

---

## 🔧 Installation & Setup
1.  **Clone the Repository**: `git clone <repository-url>`
2.  **Install Dependencies**: `flutter pub get`
3.  **Firebase Config**: Place your `google-services.json` in `android/app/`.
4.  **Clean & Run**:
    ```bash
    flutter clean
    flutter run
    ```

---

## 🔐 Security & Privacy
*   **Data Isolation**: Firestore Security Rules ensure users can only access data belonging to their unique UID.
*   **Privacy First**: Medical history and health profiles are stored securely and never shared with 3rd parties.

---

**MediSense** - *Reliability when it matters most.* 🩺🚀
