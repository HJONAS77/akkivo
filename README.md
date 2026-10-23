# Akkivo

En Android-app för alternativ och kompletterande kommunikation, byggd med Flutter. Brädor, bilder och ljud lagras privat på enheten. Ingen backend, inloggning, annonsering eller analys finns. Release-manifestet begär inte internetåtkomst. Androids systemnavigation är tillgänglig även i skyddat användarläge.

## Kom igång

Kräver Flutter stable (utvecklad med 3.47.8 / Dart 3.13.7), Android SDK och JDK via Android Studio. Android är den enda konfigurerade plattformen.

```powershell
cd C:\Repo\akkivo
flutter pub get
flutter doctor -v
flutter run
```

Om Flutter saknas i terminalens PATH kan du använda `& 'C:\Users\JonasCarlsson\flutter\bin\flutter.bat'` i stället för `flutter`. Det påverkar inte din vanliga användares PATH.

Första starten innehåller två textbaserade exempelbrädor: **Min vardag** och **Så känner jag**. Egna bilder kan läggas till med Androids bildväljare. Inga externa symbolbibliotek medföljer.

## Användning

- Tryck på ord för att bygga ett meddelande. **Läs upp**, **Ta bort senaste ordet** och **Rensa** finns vid meddelanderaden. Ja/Nej läses upp direkt. Känslor öppnar en annan bräda.
- Öppna menyn **Administration → Mina brädor** för att skapa brädor. Menyn vid varje bräda ändrar namn/rutnät, väljer startbräda eller tar bort brädan. Startbrädan och brädor som andra brädor länkar till kan inte tas bort direkt.
- Välj **Redigera celler** och tryck på en cell, inklusive tomma positioner. Ange text, eventuell separat taltext, bild, färg och åtgärd. Flytta cellen genom att välja en ledig rad/kolumn. En krympning av rutnätet stoppas om celler skulle försvinna.
- Välj **Förhandsgranska** för att prova brädan. Förhandsvisningen är administrationsläge och håller inte skärmen tänd.
- Välj **Starta skyddat användarläge**, skapa en PIN-kod och spara den säkert. Låsikonen begär PIN för återgång till administration. Meddelandet sparas inte mellan processstarter; brädor och aktivt skyddat läge sparas.
- Importera `.obf` eller `.obz` från menyn. Brädor med samma ID ersätts efter en bekräftelse; övriga brädor och startbrädeinställningen behålls. Importens rotbräda öppnas efteråt. Exportera OBZ för en komplett säkerhetskopia av brädor och stödd media. PIN och skyddat läge ingår inte i exporten.

## Tal och ljud

Svenska offline-röstdata måste finnas i Androids inställningar för text-till-tal. Installera dem vid behov och starta om Akkivo. Appen väljer en svensk röst som inte kräver nätverk och ger ett felmeddelande om motor eller röstdata saknas. Testa uppläsning i flygplansläge på den aktuella enheten innan appen tas i bruk. Ljudvolymen styrs med Androids vanliga volymreglage.

## PIN och återställning

PIN-koder lagras som PBKDF2-HMAC-SHA256 med 600 000 iterationer, 128 bitars slumpmässigt salt och 256 bitars verifierare. Beräkningen görs utanför UI-isolaten. Verifieraren och försöksräknaren har en separat SQLite-tabell i appens privata lagring; ingen PIN i klartext sparas. Efter tre felaktiga försök börjar en beständig fördröjning på 5 sekunder, som ökar till högst 5 minuter. En pågående verifiering kan inte startas parallellt. Androids automatiska appbackup är avstängd.

**Glömd PIN:** exportera OBZ-säkerhetskopior i förväg och förvara dem säkert. Gå sedan till **Android-inställningar → Appar → Akkivo → Lagring → Rensa appdata**, eller avinstallera och installera om appen. Det raderar alla lokala brädor och all media samt PIN-koden. Importera din OBZ-kopia efteråt. Utan säkerhetskopia går lokal information förlorad. Det finns ingen bakdörr eller universell PIN.

Skyddet förhindrar administration i appen. Det är inget Android-kioskläge och skyddar inte mot någon som har administrativ åtkomst till själva enheten eller kan rensa appdata.

## Struktur

`lib/domain` innehåller brädor, typade cellåtgärder, meddelandebyggare, brädnavigering och tjänstegränssnitt. `lib/data` innehåller SQLite, PIN, lokal media och OBF/OBZ. `lib/application` samordnar dem. `lib/presentation` innehåller brädvyn och de små redigeringsdialogerna. Android-lagret i `MainActivity.kt` sköter inbyggd TTS, MediaPlayer och `FLAG_KEEP_SCREEN_ON` bakom en MethodChannel.

SQLite har versionerat schema (v1) och främmande nycklar. Alla administrativa databasändringar kontrollerar beständigt läge **inne i transaktionen**. Import ersätter brädinnehåll i en gemensam transaktion efter fullständig paketvalidering. Media har innehållsbaserade filnamn och skrivs atomärt före transaktionen. Misslyckad import kan lämna oanvända privata mediafiler men ändrar inga befintliga brädor. Mediafiler raderas inte automatiskt i MVP:n, så delade bilder kan inte försvinna när en cell tas bort.

Rutnätet har bestämda rader och kolumner; smala/låga skärmar får rullning i stället för att celler flyttas om. Celler har minst 96 × 108 logiska pixlar, text, tillgänglighetsetiketter och tryckåterkoppling. Textskalning stöds. Stora brädor kan behöva rullas.

## OBF / OBZ

Se [formatstöd och gränser](docs/FORMAT.md). Implementationen utgår från [Open Board Formats officiella specifikation](https://www.openboardformat.org/docs), dess [publicerade specifikationsdokument](https://docs.google.com/document/d/1Bnl5neOf9-y53yOAGjd8BzQ7jvAdLhcB6y9Zw7ITYbA/edit) och [OpenAAC:s källkod](https://github.com/open-aac/openboardformat). Den gör inte anspråk på full kompatibilitet.

## Verifiering och bygge

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter test integration_test/app_test.dart -d emulator-5554
flutter build apk --debug
```

APK:n hamnar i `build/app/outputs/flutter-apk/app-debug.apk`. Debugbygget är avsett för utveckling och enhetstest. För distribution behövs egen release-signering; den genererade releasekonfigurationen använder ännu debugnyckeln och ska ändras före publicering.

Enhets- och widgettester täcker cellåtgärder, meddelanden, PIN, beständig låsning, fördröjning, skärmstatus, navigering, dataintegritet och formatvalidering/roundtrip. Android-integrationstestet kräver en startad emulator eller ansluten telefon. Native röstkvalitet och bild-/filväljarens systemdialoger behöver också provas på verkliga målenheter.

Fullt kioskläge, molnsynkronisering, symbolbibliotek, grammatikkorrigering, scanning, brytarstyrning och iOS ingår inte.
