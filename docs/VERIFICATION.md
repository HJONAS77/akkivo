# Verifiering 2026-10-24

Miljö: Windows, Flutter 3.47.8 stable, Dart 3.13.7, Android Studio JDK 25, Android SDK och emulator `Medium_Phone_API_37.0`.

| Kontroll | Resultat |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | 15 filer, inga formatteringsändringar |
| `flutter analyze` | Inga anmärkningar; inga nya lint-undantag |
| `flutter test --reporter expanded` | 18 tester godkända |
| `flutter test integration_test/app_test.dart -d emulator-5554 --reporter expanded` | 1 Android-integrationstest godkänt |
| `flutter build apk --debug` | Godkänt: `build/app/outputs/flutter-apk/app-debug.apk` |

Enhetstesterna använder riktig SQLite via FFI, tillfälliga privata mediafiler och falska enhetstjänster. Widgettesterna provar telefon, surfplatta, liggande format och dubblerad textskalning. De täcker också felaktig respektive korrekt PIN via dialogen.

Android-testet använder Androids SQLite-plugin och det riktiga MethodChannel-lagret. Det skapar en bräda och cell via gränssnittet, aktiverar celler, bygger meddelande, navigerar mellan brädor, gör OBZ-roundtrip, blockerar administration under låsning och kontrollerar skyddat läge efter att databasen stängts och öppnats på nytt. Livscykelstyrningen anropar det riktiga Android-lagret. Detta är inte ett test med fysisk avstängning av telefonen.

Första Android-bygget installerade NDK 28.2.13676358, SDK Platform 35/36 och CMake 3.22.1. Den nya SDK-hanterarens bakåtkompatibla `sdkmanager.bat` kunde inte tolka NDK-anropet från Flutter. Direkt installation med följande kommando löste det:

```powershell
& "$env:LOCALAPPDATA\Android\sdk\cmdline-tools\latest\bin\android.exe" --no-metrics sdk install 'ndk;28.2.13676358'
```

Integrationstestets första körning avslöjade att testet behövde invänta asynkron databassparning innan nästa tryck. Den slutliga körningen använder ett uttryckligt väntvillkor för sparad bräda/cell och stängd dialog.

Kvar att prova på en fysisk målenhet: svensk offline-TTS och röstkvalitet, systemets bild-/filväljare, ljudfiler i de aktuella Android-avkodarna samt bakgrund/processdöd/omstart från Androids faktiska systemgränssnitt. Produktionsdistribution kräver egen release-signering. Se även `FORMAT.md` för avgränsat OBF/OBZ-stöd.

