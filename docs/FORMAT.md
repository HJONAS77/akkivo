# Stött delmängd av Open Board Format

Referens: [Open Board Format](https://www.openboardformat.org/docs), `open-board-0.1`. Den officiella specifikationen lästes inför implementationen. Filformatet är inte en egen JSON-layout med OBF-filändelse.

| Del | Stöd |
| --- | --- |
| OBF | En UTF-8-JSON-bräda med `format`, sträng-ID, namn, `buttons`, `grid`, `images`, `sounds` |
| OBZ | ZIP med OBF-brädor, lokala resurser och `manifest.json` med `root` och `paths.boards/images/sounds` |
| Positioner | `grid.rows`, `columns`, `order` med sträng-ID eller `null` |
| Länkar | `load_board.id` / `load_board.path` inom importpaketet |
| Text | `label`, valfri `vocalization` |
| Färger | `rgb()` och `rgba()`; alfa blandas mot vitt, export skriver `rgb()` |
| Bilder | PNG, JPEG, WebP från `data` som data-URI eller `path` i OBZ |
| Ljud | MP3, M4A, WAV, OGG via `sounds` och `sound_id`; Android avkodar vid uppspelning |
| Åtgärder | Standardknappar läses upp; `load_board` navigerar; `sound_id` spelar ljud |
| Meddelandebyggande | `ext_akkivo_action: "addToMessage"`, en uttrycklig apputökning enligt specifikationens `ext_`-konvention. Andra appar kan ignorera den och läsa upp texten direkt. |
| Licenser | `license` för brädor/bilder/ljud behålls; media utan licens behandlas som privat |
| Språkmetadata | `locale` behålls men uppläsning är svenska i denna MVP |

OBF-export bäddar in bilder och ljud som data-URI. Brädor med länkar måste exporteras som OBZ. OBZ-export innehåller samtliga brädor och har den valda startbrädan som `root`. Bräd-, cell-ID:n, tomma positioner och länkar bevaras. Lokala media-ID:n kan ändras till innehållsbaserade namn vid import; bild- och ljudinnehållet bevaras. Importerade brädor med samma ID ersätter motsvarande brädor atomärt efter bekräftelse. Inställd startbräda ändras inte av import.

Stöds inte: webbhämtning av externa resurser eller brädlänkar, proprietära symbolbibliotek, SVG/GIF, `strings`-översättningar, absolut placering, kantfärger, specialåtgärder såsom `:clear`, `+a` eller flera `actions`. Specialåtgärder och externa brädlänkar avvisas med felmeddelande. Externa media/symboler utan lokal data ger varning och tom bild/text som platshållare. Okänd metadata och okända utökningar bevaras inte generellt. Upprepade knapp-ID:n i flera rutpositioner inom samma bräda avvisas i denna MVP. Färgsyntax som inte stöds får appens standardfärg.

## Validering

- Infil högst 30 MB; uppackat innehåll högst 60 MB; högst 500 ZIP-poster och 100 brädor.
- Varje mediafil högst 10 MB; varje JSON-fil högst 2 MB. Rutnät 1–10 rader och 1–10 kolumner. Namn högst 200 tecken, celltext/taltext högst 2000.
- Absoluta sökvägar, `..`, `.`, kolon, bakstreck, procentkodning, kontrolltecken, dubbletter (även skiftlägesvarianter), symboliska länkar, krypterade paket och mycket höga kompressionskvoter avvisas.
- ZIP-centralregistret kontrolleras innan data avkodas. Längder och CRC kontrolleras också. Arkivets sökvägar används aldrig för att skriva filer på disk.
- Manifest, resurser, unika ID:n, rutnätsdimensioner, referenser och interna brädlänkar kontrolleras före databastransaktionen. Trasiga eller saknade paketerade resurser avvisas.
- Bildsignaturer kontrolleras. Bild som inte kan renderas visas som en platshållare; ljud som Android inte kan avkoda ger uppspelningsfel.
- Validering sker på separat Dart-isolat. Nya privata filer får innehållsbaserade filnamn. Befintlig media skrivs inte över. Brädbytet görs i en enda SQLite-transaktion.

En säkerhetskopia som ligger utanför dessa gränser kan behöva delas upp. Exporten kontrolleras mot samma begränsningar innan den sparas, så att appen inte erbjuder en egen säkerhetskopia som inte kan återimporteras.
