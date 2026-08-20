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

## Note

On the first run, macOS will ask for calendar access. Calmir only updates or deletes destination events it created.

## Help

Show usage options for a specific subcommand:

```bash
swift run calmir help sync
```
