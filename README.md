# Petsy (Flutter)

Flutter client for Petsy, ported from the Expo app in
[steev2058/petsy_dashboard](https://github.com/steev2058/petsy_dashboard). It talks to the same FastAPI backend.

Arabic (RTL) is the default language; English can be toggled from the home screen, login screen or profile.

## Run

```bash
flutter pub get
flutter run                     # uses https://petsy.company/api
```

Point the app at another backend with `--dart-define`:

```bash
# Android emulator -> backend on the host machine
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api

# Web against a local backend (add the web origin to the backend's CORS_ORIGINS)
flutter run -d chrome --web-port 8088 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Plain `http://` backends on Android release builds also need cleartext traffic enabled in
`android/app/src/main/AndroidManifest.xml`.

## Structure

```
lib/
  core/        config (API URL), theme, translations (ar/en), Dio API client
  models/      JSON models matching backend/server.py
  services/    PetsyApi – one method per backend endpoint used by the app
  state/       AuthState (token + user), LocaleState, CartState (persisted locally)
  widgets/     shared widgets (AsyncView loader, cards, chips, composer)
  screens/     auth, home, pets/adoption, shop/cart/orders, vets/appointments,
               community, messages/chat, notifications, profile
  router.dart  go_router routes, bottom tabs, login guard
```

## Screens included

Login, signup, email verification, password reset · Home · Adoption + pet details (contact owner) ·
My pets + add pet · Shop + product details · Cart, checkout (cash on delivery), order history ·
Vets directory, vet profile, book/cancel appointments · Community feed, post + comments, new post ·
Conversations + chat · Notifications · Profile + edit profile + language.

Not yet ported from the Expo app: admin dashboard, vet/clinic/market-owner tools, marketplace listings,
sponsorships, lost & found, health records, pet tags/QR, map, emergency contacts, AI assistant,
friends/blocking, privacy settings, card/ShamCash payments.

## Tests

```bash
flutter analyze
flutter test
```
