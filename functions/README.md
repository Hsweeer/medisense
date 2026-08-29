MediSense Cloud Functions

This folder contains Firebase Cloud Functions used by the MediSense app for SOS alerts and tracking.

What is included
- src/index.ts — Callable functions: sendSosAlert, updateSosTrackingStatus, getSosTrackingSession
- tsconfig.json — TypeScript compiler config
- package.json — Functions dependencies (firebase-admin, firebase-functions, twilio)
- .env.example — example environment variables (TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER)

Local development and tests (recommended)
1. Install dependencies:
   cd functions
   npm install

2. Use the Firebase emulator (recommended for safe testing):
   - Start the emulator (functions + firestore):
     firebase emulators:start --only functions,firestore
   - In another terminal, run a small script or the Flutter app pointed at the emulator:
     - Set FIREBASE_EMULATOR_HOST / other env variables as needed or use firebase-tools emulator UI.

Setting Twilio / runtime configuration (server-side secrets)
- Do NOT put Twilio credentials in the Flutter app.
- Use Firebase runtime config instead:
  firebase functions:config:set twilio.account_sid="YOUR_SID" twilio.auth_token="YOUR_TOKEN" twilio.from="+1234567890"
- After setting runtime config, deploy functions (or restart emulator) so that functions.config() picks up the values.

Deployment (requires firebase CLI and project access)
1. Login:
   firebase login
2. Select project (optional):
   firebase use --add
   # choose 'medisense-7144b' or set default project
3. Deploy functions and Firestore rules:
   firebase deploy --only functions,firestore:rules

Validation checklist after deploy
- Callables are available (use emulator or production SDK): sendSosAlert, updateSosTrackingStatus, getSosTrackingSession
- When sendSosAlert is called with valid contacts and Twilio config present, SMS are sent and Firestore fields in sos_sessions update accordingly.
- Tracking session documents are written to tracking_sessions with proper expiry and accessRestricted flag behavior.

Security notes
- Keep Twilio credentials secret; use Firebase runtime config or a secrets manager.
- Firestore rules in the repository must be deployed to enforce access control.

If you want, I can attempt to deploy from this environment now — but you must provide Twilio credentials or allow a dry-run and accept that the CLI will require authentication. Alternatively, run the deploy commands locally on your machine following these steps above.
