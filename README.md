# Calmir

A macOS CLI tool for syncing calendar events.

## Prerequisites

- macOS >= 14
- Swift >= 6.2

## Usage

List calendar names and identifiers

```bash
swift run calmir list
```

Sync next `N` days (default: 7)

```bash
swift run calmir sync --from "source name" --to "destination" --days 7
```

Sync current week

```bash
swift run calmir sync --from "source name" --to "destination name" --week
```

## Skipping events

Put `nosync` anywhere in an event's description (notes) and calmir ignores that event — the match is
case-insensitive, so `NoSync` and `#NOSYNC` work too.

- On a **source** event: it's never copied to the destination. If it was mirrored before you added the
  marker, the mirror is removed on the next sync.
- On a **destination** event: calmir never updates or deletes it, but it still counts as the mirror of
  its source event, so no duplicate is created next to it.

## Note

On the first run, macOS will ask for calendar access. Calmir only updates or deletes destination events it created.

## Help

Show usage options for a specific subcommand:

```bash
swift run calmir help sync
```
