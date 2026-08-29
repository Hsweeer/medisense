# 🏥 MediSense - Smart Health Companion

MediSense is a professional, production-ready Flutter application designed to empower patients with AI-driven insights, automated medication reminders, and a robust real-time emergency SOS system.

## 🚀 Key Features

### 🚨 Critical SOS System (High Availability)
*   **Real-Time Tracking**: Continuous GPS tracking with background service support to keep responders informed even when the app is backgrounded.
*   **Intelligent Routing**: Real road route calculation using OSRM, providing accurate distance and ETA to the nearest hospitals.
*   **Country-Aware Emergency Services**: Dynamic resolution of emergency numbers (Police, Ambulance, Fire) based on the user's current GPS location (Supports PK, US, UK, AE, etc.).
*   **Secure Tracking Sessions**: Generates unique, time-bound tracking tokens for emergency contacts to monitor the user's location via a secure web/app view.
*   **Dual-Trigger Mechanism**: Activate SOS via the in-app dashboard or the system-wide Floating Accessibility Button.

### 🤖 MedAI - Intelligent Assistant
*   **Prescription Scanner**: Advanced two-pass OCR (Gemini 1.5 Flash) that transcribes and structures handwritten prescriptions into actionable medication data.
*   **Voice-to-Text Chat**: Hands-free interaction using Groq's Whisper API for high-speed, accurate transcription.
*   **Personalized Insights**: AI replies tailored to the user's Medical ID, including allergies, conditions, and weight/height context.
*   **Auto-Reminders**: MedAI can directly set medication alarms in the app through natural language commands (Function Calling).

### 💊 Medication Management
*   **Smart Reminders**: Robust alarm system with snooze functionality and full-screen alerts.
*   **Medical ID**: A centralized health profile containing blood type, allergies, and chronic conditions, shared securely with emergency responders.

### 🍏 Nutrition & Wellness
*   **Food Scanner**: Scan food items to get instant nutritional insights and log daily intake.
*   **Nearby Care**: Locate the nearest hospitals and pharmacies using OpenStreetMap (Overpass API) with live "Open/Closed" status.

## 🛠 Tech Stack

*   **Framework**: Flutter (Dart)
*   **Backend**: Firebase (Auth, Firestore, Cloud Functions, Storage)
*   **AI Engines**: 
    *   **Groq**: Llama 3.3 (Chat) & Whisper (Voice)
    *   **Google Gemini**: Vision AI (Prescription OCR)
*   **Maps**: Flutter Map with OpenStreetMap & OSRM Routing
*   **Local Services**: Google ML Kit (Offline OCR), Flutter Local Notifications, Native Android Broadcasts

## 📁 Project Structure

```
lib/
├── core/               # App architecture, themes, and shared logic
│   ├── config/         # API Keys and Environment settings
│   ├── services/       # Core business logic (Location, Routing, AI)
│   └── widgets/        # Reusable UI components
├── data/               # Data layer
│   ├── models/         # Type-safe data structures
│   └── mock/           # Mock data for testing and previews
├── features/           # Modular feature implementations
│   ├── sos/            # Emergency SOS flow
│   ├── chat/           # MedAI Chat & Scanner
│   ├── reminders/      # Medication Alarms
│   └── profile/        # Medical ID & Health Profile
├── providers/          # State management (ChangeNotifier/Provider)
└── services/           # Backend-specific services (Firestore/Cloud Functions)
```

## 🔐 Security & Privacy
*   **API Security**: Sensitive keys are managed via `.env` files and never hardcoded in the source.
*   **Data Isolation**: Firestore security rules ensure users can only access their own medical data.
*   **Secure Tracking**: SOS tracking links use non-guessable UUID tokens that expire after the emergency is resolved.

---
Developed with ❤️ for Patient Safety.
