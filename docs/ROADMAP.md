# Fahrplan

Reihenfolge: **erst lauffähig und spaßig, dann Aussehen, dann Monetarisierung, dann Launch und
Live-Updates.**

Warum: Roblox empfiehlt Spiele vor allem nach Spielzeit und danach, ob Spieler wiederkommen.
Monetarisierung in einem Spiel, das niemand länger als 5 Minuten spielt, bringt nichts. Sie
kommt aber vor den öffentlichen Launch, damit die erste Spielerwelle schon kaufen kann.

| Phase | Was | Dauer (grob) | Fertig, wenn … |
| --- | --- | --- | --- |
| **0. Zum Laufen bringen** | Studio-Checkliste aus [TESTING.md](TESTING.md) durchgehen, Laufzeitfehler fixen, privat veröffentlichen, Speichern testen | 1–3 Tage | Solo und mit 3 Spielern läuft alles ohne Fehler im Output |
| **1. Kernspaß** | Tutorial-Ablauf, Balancing, Handy-Bedienung, Heist-Fairness | 1–2 Wochen | Freunde spielen freiwillig 20+ Minuten; erste Mutation nach unter 3 Minuten, erstes neues Biom nach unter 15 Minuten |
| **2. Design / Look** | Bessere Kreaturen-Modelle, Effekte, Musik, Sounds, Insel-Optik, **Icon + Thumbnails** | 1–2 Wochen | Screenshots sehen „klickbar“ aus. Icon und Thumbnails entscheiden, wie oft das Spiel angeklickt wird |
| **3. Monetarisierung + Analytics** | 2× Coins, Starter-Pack, Mutation sofort fertig, Zeitboosts; dazu Auswertungen über `AnalyticsService` (wo springen Spieler ab, wofür wird was ausgegeben) | ca. 1 Woche | Käufe funktionieren in Studio-Testkäufen, Daten kommen an |
| **4. Launch** | Öffentlich schalten, kleines Werbebudget (Roblox Ads), Zahlen beobachten | laufend | Kennzahlen bekannt: Wiederkehrer nach 1 und 7 Tagen, Spielzeit, Käuferquote |
| **5. Live-Updates** | Alle 1–2 Wochen neue Kreaturen, Events, limitierte Mutationen; Preise anhand der Daten anpassen | laufend | Spieler kommen wieder, Updates bringen Traffic-Spitzen |

## Schon vorher mitdenken (nicht bauen)

- Beim Balancing in Phase 1 Platz für einen ×2-Boost einplanen, sonst wird der Pass später zu
  stark oder zu schwach.
- Datenfelder für Zeitboosts lassen sich in Phase 3 sauber nachrüsten; jetzt nichts vorbereiten.

## Leitlinien für Phase 3 (Monetarisierung)

- **Tempo verkaufen, nicht exklusive Macht:** Multiplikatoren, Zeitersparnis, Komfort.
- **Bei Heists Verteidigung verkaufen, keine Angriffskraft** (kein schnelleres Klauen, kein
  Umgehen von Schutz).
- **Bezahlten Gesamtmultiplikator deckeln** (z. B. ×4); keine Robux-Kreatur, die stärker ist
  als alles Erspielbare.
- **Roblox-Regeln:** Zufallskäufe (Eier, Lootboxen) nur mit angezeigten Chancen vor dem Kauf;
  keine falschen Countdowns oder Kaufdruck. Feste Pakete sind einfacher und sicherer.

## Nächster Schritt

Phase 0: In Studio mit ▶ starten, Fehler aus dem Output-Fenster sammeln und fixen.
