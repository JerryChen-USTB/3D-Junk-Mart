# app

Flutter frontend for the Junk Mart demo.

## Run
1. `flutter pub get`
2. Start the local backend first.
3. Run Flutter with a reachable backend host:

```powershell
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The app opens on the auth demo gate first. Use sign in or continue as guest to enter the marketplace shell.

The app accepts either a host root like `http://127.0.0.1:8000` or a full API root like `http://127.0.0.1:8000/api/v1`.

Use `flutter run -d android` for a connected phone, or `flutter run -d windows` / `flutter run -d chrome` for desktop and web targets.

### Device notes
- USB real device: run `adb reverse tcp:8000 tcp:8000`, then use `http://127.0.0.1:8000`.
- Android emulator: use `http://10.0.2.2:8000`.
- Same-LAN phone: use `http://<your-computer-ip>:8000`.

## Build
- `flutter build apk --debug`

## Notes
- The app is split into `lib/app`, `lib/features`, `lib/navigation`, `lib/theme`, and `lib/widgets`.
- Demo navigation is wired so the main tabs and detail flows are reachable after a fresh pull.
