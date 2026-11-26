# LELOMUHLE_BOT — phone-only signal app (Milestone 1)

## Current behaviour
- Standalone Flutter app; no app-account login, backend URL, Windows PC, MT5 terminal, broker login, or VPS is needed for signal calculations.
- Downloads XAUUSD and US30 M5 candles and a fresh bid/ask quote from the initial Biquote public reference-feed adapter.
- Calculates EMA(50/200), RSI(14), MACD(12/26/9), and ATR(14) on the phone using completed candles only.
- Displays BUY, SELL, or WAIT plus reference bid/ask, entry, stop loss, take profit, RSI, source, and quote time.
- No broker connection and no order-placement code are used by this screen. Automatic trading is disabled.
- Refreshes once per minute while the app is foregrounded; manual pull-to-refresh is available.

## Important limitations
- This project has not been compiled or run in this environment because Flutter/Dart SDKs are unavailable here. Run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk --debug` on a machine with Flutter installed before treating it as install-ready.
- The Biquote adapter is an initial candidate integration and has not been runtime-verified from this Flutter app. Feed availability can vary by symbol and market state. If a quote/candle request fails or is stale, the app should show WAIT rather than fabricate prices.
- Biquote is a separate reference feed, not the user's broker. Prices, spreads, candle construction, symbol definitions and trading hours may differ. Never assume the displayed price is executable at a broker.
- The configured spread filters (XAUUSD 1.50, US30 10.0) are provisional reference filters, not calibrated to a specific broker. Treat them as conservative software checks, not broker guarantees.
- Refresh stops when Android backgrounds or force-stops the app. Background notifications and scheduled work are not implemented. The phone does not promise uninterrupted M5 alerts while closed.
- Internet access is required. Signals are informational and do not guarantee profitability.

## Build on Windows
1. Install Flutter and Android Studio / Android SDK.
2. Open a terminal in the project root (the folder containing `pubspec.yaml`).
3. Run `flutter doctor` and resolve Android toolchain issues.
4. Run `flutter pub get`.
5. Run `flutter analyze` and `flutter test`.
6. Connect an Android phone with USB debugging enabled, or use an emulator, and run `flutter run`.
7. To create a debug APK, run `flutter build apk --debug`. The APK is normally created at `build/app/outputs/flutter-apk/app-debug.apk`.

The Android `local.properties` file is intentionally omitted because it contains machine-specific SDK paths; Flutter/Gradle regenerates it for the local installation.
