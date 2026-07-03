# Spec: Storage-basierter Config-Sync für tsm

**Datum:** 2026-07-03
**Status:** Entwurf (vom Nutzer freigegeben: Design-Gespräch am 2026-07-03)

## Ziel

Die tsm-Serverkonfiguration (`~/.config/tsm/servers`) wird zwischen allen
Installationen über den storage-for-agents-Service geteilt, statt wie bisher
per SSH-Push/Pull gegen einen ausgezeichneten "Main Server". Der SSH-Sync und
das Main-Server-Konzept entfallen vollständig.

## Hintergrund

Heute synchronisiert tsm die Server-Liste per SSH mit einem Main-Server
(`is_main`-Flag, Tasten `m` und `s` im Config-Menü, Methoden
`push_config_to_main`, `push_config_to_server`, `pull_config_from_main`).
Das setzt voraus, dass der Main-Server erreichbar ist und alle Maschinen ihn
per SSH erreichen. storage-for-agents ist eine bereits deployte, von allen
Maschinen erreichbare Instanz eines S3-artigen Objektspeichers mit
Bearer-Token-Auth und Presigned-URL-Transfer — die Config kann dort zentral
liegen.

## Entscheidungen (aus dem Design-Gespräch)

| Frage | Entscheidung |
|---|---|
| Deployment | Instanz läuft bereits, wird direkt genutzt |
| Verhältnis zum SSH-Sync | Kompletter Ersatz, SSH-Sync wird entfernt |
| Sync-Timing | Automatisch (Pull beim Start, Push bei jeder Änderung) |
| Konflikte | Last-Write-Wins (ganze Datei) |

## Architektur

### Speicherort

- Ein Bucket `tsm`, ein Objekt mit Key `servers`.
- Inhalt: die `servers`-Datei im bestehenden Pipe-Format (ohne `is_main`-Spalte,
  siehe Migration).

### Transport

REST-API von storage-for-agents, ausschließlich mit Ruby-Stdlib (`net/http`,
`json`) — tsm bleibt zero-dependency. Byte-Transfer ist zweistufig:

1. `POST {storage_url}/api/buckets/tsm/objects/presign` mit
   `Authorization: Bearer {storage_token}` und Body
   `{"op":"put"|"get","key":"servers"}` → liefert `url`.
2. `PUT` (Upload) bzw. `GET` (Download) auf diese URL.

Bucket-Anlage: `PUT {storage_url}/api/buckets/tsm` ist idempotent und wird vor
dem ersten Push einmalig aufgerufen (bzw. bei 404 des Presign nachgeholt).

### Konfiguration

`~/.config/tsm/config` erhält zwei neue Schlüssel:

```
storage_url=https://storage-for-agents.example.com
storage_token=store:...
```

Fehlt einer der beiden Schlüssel, läuft tsm im lokalen Modus: kein Sync,
kein Fehler; das Config-Menü zeigt "no storage configured".

### Neues Modul: `StorageSync`

Eigenes Modul im Single-File-Skript (analog `UpdateChecker`), Verantwortung:

- `configured?` — beide Config-Schlüssel vorhanden?
- `pull` — Datei herunterladen, Rückgabe: Inhalt oder `nil` (Fehler/Timeout/404).
- `push(content)` — Datei hochladen, Rückgabe: true/false.
- `status` — letzter Sync-Zustand für die Statuszeile
  ("synced Xm ago" / "offline" / "no storage configured").

Alle HTTP-Aufrufe mit Timeout (neue Konstante `STORAGE_TIMEOUT = 5`,
analog `SSH_TIMEOUT`). Fehler werden nie zu Exceptions nach außen, sondern
zu `nil`/`false` + Statusanzeige.

## Sync-Verhalten

### Pull beim Start

- Beim TUI-Start startet ein eigener Thread (Muster wie `UpdateChecker.check_async`
  bzw. `start_async_fetch`), der `StorageSync.pull` aufruft.
- Bei Erfolg: lokale `servers`-Datei atomar ersetzen, Server-/Session-Liste
  neu aufbauen und neu rendern. `ensure_self_entry!` läuft danach — fehlt der
  eigene Eintrag in der Remote-Liste, wird er ergänzt und sofort gepusht.
- Bei Fehler/Offline: stiller Fallback auf die lokale Datei, Status "offline".
- Auch die CLI-Pfade (`tsm <server> [session]`) arbeiten rein mit der lokalen
  Datei — kein Pull, damit Attach nie auf HTTP wartet.

### Push bei Änderung

Jede lokale Änderung der Server-Liste pusht sofort die komplette Datei:

- Server hinzufügen (`add_server_dialog`)
- Server entfernen (`delete_server_dialog`)
- `ensure_self_entry!` / Claim / Migration, wenn sie die Datei verändert haben

Last-Write-Wins: die zuletzt pushende Maschine überschreibt den zentralen
Stand vollständig. Parallele Änderungen auf zwei Maschinen können sich
gegenseitig überschreiben — bewusst akzeptiert (persönliches Tool, seltene
konkurrierende Änderungen). Ein fehlgeschlagener Push wird nicht gequeued;
die lokale Datei bleibt die Arbeitskopie und der nächste Push/Start gleicht
implizit an.

## Rückbau des SSH-Syncs

Entfernt werden:

- `is_main`-Spalte im Dateiformat, `Server#is_main`, `ServerManager.main_server`,
  `ServerManager.set_main`, das `[main]`-Suffix in `Server#display_name`
- `sync_servers_dialog`, `push_config_to_main`, `push_config_to_server`,
  `pull_config_from_main`, `set_main_server`
- Tasten `m` und `s` im Server-Config-Menü (inkl. Hilfezeile und README)

Bestehen bleibt:

- `MachineId` unverändert — jede Maschine erkennt ihren eigenen Eintrag in der
  geteilten Liste (`local?`), inkl. Claim-Mechanismus.
- `ensure_tsm_on_server` (Selbst-Installation auf neuen Servern), erweitert um
  Token-Verteilung (siehe unten).

### Migration des Dateiformats

Aktuelles Format (6 Spalten): `alias|host|user|port|is_main|machine_id`.
Neues Format (5 Spalten): `alias|host|user|port|machine_id`.

`ServerManager.load_servers` unterscheidet beim Parsen positionsabhängig:
bei 6 Feldern ist `parts[4]` das (ignorierte) `is_main`-Flag und `parts[5]`
die machine_id; bei ≤5 Feldern ist `parts[4]` die machine_id. Zur Absicherung
gilt zusätzlich: ist `parts[4]` exakt `true` oder `false`, wird es als
Legacy-`is_main` behandelt (machine_ids sind Hex-UUIDs, kollidieren also nie
mit diesen Werten). Geschrieben wird nur noch 5-spaltig. Kein separater
Migrationsschritt — die Datei wird beim ersten Schreiben konvertiert.
README-Beispiele werden angepasst (das README zeigt heute fälschlich ein
5-spaltiges Format mit `is_main` am Ende).

## Token-Verteilung an neue Installationen

Wenn tsm sich beim Hinzufügen eines Servers dort selbst installiert
(`ensure_tsm_on_server`), kopiert es zusätzlich `~/.config/tsm/config`
(mit `storage_url` + `storage_token`) per SSH auf den Zielserver — vorhandene
fremde Schlüssel in einer dortigen Config werden dabei nicht zerstört:
existiert remote bereits eine Config, werden nur `storage_url`/`storage_token`
gesetzt/ersetzt. Neue Installationen sind damit sofort sync-fähig.

## UI-Änderungen

- Server-Config-Menü: Statuszeile mit Sync-Zustand
  ("synced 2m ago" / "offline" / "no storage configured").
- Hilfezeilen (Haupt-TUI und Config-Menü) und README: `m`/`s` entfernen,
  Sync-Abschnitt neu beschreiben.
- Keine neue Taste: Sync ist vollautomatisch.

## Fehlerbehandlung

- Alle HTTP-Aufrufe mit `STORAGE_TIMEOUT` (5 s), Fehler → `nil`/`false`.
- Sync-Fehler blockieren nie die TUI und erzeugen keine Dialoge — nur die
  Statuszeile ändert sich.
- HTTP 401/403 (Token ungültig) wird in der Statuszeile unterscheidbar
  angezeigt ("auth failed"), damit ein rotierter Token auffällt.
- Redirects der Presigned URL werden nicht erwartet; `net/http` folgt ihnen
  nicht automatisch — falls der Service welche liefert, wird genau ein
  Redirect gefolgt.

## Tests / Verifikation

Das Projekt hat keine Test-Suite; Verifikation manuell:

1. Lokale Instanz oder deployte Instanz: Push erzeugt Objekt
   (per `curl` gegen die REST-API prüfbar), Pull auf zweiter
   Maschine/zweitem `$HOME` übernimmt die Liste.
2. Offline-Fall: Netzwerk kappen → TUI startet unverändert, Status "offline".
3. Ohne Config-Schlüssel: Verhalten wie bisher, Status "no storage configured".
4. Alte 5-spaltige `servers`-Datei wird korrekt gelesen und beim nächsten
   Schreiben konvertiert.

## Offene Punkte

- Basis-URL der deployten Instanz und ein provisionierter `store:`-Bearer-Token
  werden für Implementierung/Verifikation benötigt (oder ein
  Provisioning-Token, um den Agent anzulegen).

## Nicht im Scope

- Verschlüsselung des Config-Inhalts im Storage (Bucket ist agent-isoliert,
  nicht public).
- Merge-/Konfliktlogik über Last-Write-Wins hinaus.
- Mehrere Profile/Buckets.
- Sync anderer Dateien als `servers`.
