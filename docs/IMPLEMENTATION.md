# Implementationsplan och verifieringssteg

1. Undersök tomt repo, Flutter/Android-verktyg och officiell OBF-specifikation. Skapa Androidprojekt.
2. Lägg till domänmodeller, SQLite v1 och separata exempeldata. Koppla brädrutnät till typad åtgärdshanterare och native TTS.
3. Lägg till meddelandebyggare, brädhistorik, cell- och brädredigerare samt privat bild/ljudlagring.
4. Lägg till PIN-verifiering, beständigt användarläge, transaktionsskydd och livscykelstyrd skärmvakenhet.
5. Lägg till validerad OBF/OBZ-import och export med transaktionsbaserat brädbyte.
6. Kör formattering, analys, enhets-/widgettester och Androidbygge. Prova centrala flöden i emulator när den finns tillgänglig.

Varje lager kan testas separat med falska tal-/enhetstjänster. SQLite-tester kör med riktig SQLite via FFI; Androidflödet använder Androids databasplugin.
