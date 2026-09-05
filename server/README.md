# MediSense notification server

This is the standalone Node.js/Firebase Admin server that replaces the old Cloud Functions notification logic so the project can stay on the Firebase Spark free plan.

## What it does

- Sends SOS alerts to registered emergency contacts
- Sends caregiver request notifications
- Sends caregiver response notifications
- Sends reminder notifications
- Handles caregiver request accept/reject actions
- Cleans stale FCM registration tokens via a cron endpoint

## Required environment variables

Set these in Render, Railway, Fly, or your host:

- `FIREBASE_PROJECT_ID` — your Firebase project ID
- `FIREBASE_CLIENT_EMAIL` — service account client email
- `FIREBASE_PRIVATE_KEY` — service account private key, including newlines escaped as `\n`
- `CRON_SECRET` or `TOKEN_CLEANUP_SECRET` — shared secret for the token cleanup endpoint

Example Render env:

```bash
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=firebase-adminsdk@your-project-id.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
CRON_SECRET=replace-with-a-random-secret
```

## Local run

```bash
cd server
npm install
cp .env.example .env
# fill in env vars
npm start
```

## Render deployment

1. Create a new Web Service on Render.
2. Connect this repository.
3. Set the root directory to `server`.
4. Build command: `npm install`
5. Start command: `node index.js`
6. Add the environment variables above.
7. Deploy.

Your app will then use the live URL, for example:

```dart
static const String _baseUrl = 'https://medisense-notify.onrender.com';
```

## Cron setup

Set up a daily request to:

```text
https://your-render-url/token-cleanup?secret=YOUR_SECRET
```

Examples:

- cron-job.org
- GitHub Actions scheduled workflow
- any external free cron provider

## Security

All non-GET endpoints require:

```http
Authorization: Bearer <Firebase ID token>
```

The server verifies the token with `admin.auth().verifyIdToken()` before processing the request.
