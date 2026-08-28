Backend deployment checklist for MediSense SOS

1. Prepare Firebase project
   - Ensure you have access to the Firebase project (project ID: medisense-7144b).
   - Install and login with the Firebase CLI: `firebase login`.

2. Set Twilio runtime config (server-side secrets)
   - Run:
     firebase functions:config:set twilio.account_sid="YOUR_SID" \
       twilio.auth_token="YOUR_TOKEN" \
       twilio.from="+1234567890"

3. Deploy Firestore rules and Functions
   - Deploy rules and functions together:
     firebase deploy --only functions,firestore:rules

4. Post-deploy validation
   - In Firebase Console → Functions: ensure functions deployed and are in OK state.
   - Test sendSosAlert from a signed-in user (use the app or the emulator) and inspect sos_sessions and tracking_sessions documents.

5. Optional: Run on Emulator for safe testing
   - Start emulator: firebase emulators:start --only functions,firestore
   - Point your app to the emulator or run integration tests.

6. Rollback and safety
   - If you need to rollback, use the functions history in Firebase Console or redeploy previous code from git tag.

Notes
- Do NOT store Twilio credentials in the Flutter app. Always use runtime config or an external secret manager.
- The functions read runtime config under `twilio.account_sid`, `twilio.auth_token`, `twilio.from`.
