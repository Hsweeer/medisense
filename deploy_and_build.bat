@echo off
REM MediSense deploy & build helper (Windows CMD)
REM Edit FIREBASE_PROJECT below before running.

SETLOCAL
nREM -- Configure your Firebase project id here --
SET FIREBASE_PROJECT=your-project-id

echo ========== MediSense: functions install & build ==========
cd /d "%~dp0functions"
echo Installing functions dependencies (may prompt)...
node "C:\Program Files\nodejs\node_modules\npm\bin\npm-cli.js" install --no-audit --no-fund
if ERRORLEVEL 1 (
  echo npm install failed.
  pause
  exit /b 1
)

echo Building functions (tsc)...
node "C:\Program Files\nodejs\node_modules\npm\bin\npm-cli.js" run build
if ERRORLEVEL 1 (
  echo functions build failed.
  pause
  exit /b 1
)

echo ========== Deploy functions ==========
echo Make sure you are logged in to firebase (interactive)
firebase login
if ERRORLEVEL 1 (
  echo firebase login failed.
  pause
  exit /b 1
)
nif "%FIREBASE_PROJECT%"=="your-project-id" (
  echo Please open this file and set FIREBASE_PROJECT to your Firebase project id, then re-run.
  pause
  exit /b 1
)

firebase use %FIREBASE_PROJECT%
if ERRORLEVEL 1 (
  echo firebase use failed. Make sure the project id is correct.
  pause
  exit /b 1
)

firebase deploy --only functions
if ERRORLEVEL 1 (
  echo functions deploy failed.
  pause
  exit /b 1
)

echo ========== Deploy Firestore rules ==========
cd /d "%~dp0.."
firebase deploy --only firestore:rules
if ERRORLEVEL 1 (
  echo firestore rules deploy failed.
  pause
  exit /b 1
)

echo ========== Build Flutter APK (debug) ==========
cd /d "%~dp0"
flutter pub get --no-precompile
flutter build apk --debug --no-shrink
if ERRORLEVEL 1 (
  echo flutter build failed.
  pause
  exit /b 1
)

echo ========== Install APK on connected device ==========
flutter install

echo Done. Verify flows in Firebase console and on device.
pause
ENDLOCAL