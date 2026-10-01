import ArgumentParser
import Foundation

struct SyncCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sync",
    abstract: "Sync events from source to destination calendar"
  )

  private static let defaultDays = 7

  @Option(
    name: .long,
    parsing: .upToNextOption,
    help: "Name(s) or identifier(s) of the source calendar(s) to sync events from"
  )
  var from: [String]

  @Option(
    name: .long,
    help: "Name or identifier of the destination calendar to sync events to"
  )
  var to: String

  @Option(
    name: .long,
    help: "Number of days to sync events for (default: \(defaultDays))"
  )
  var days: Int = defaultDays

  @Flag(
    name: [
      .customLong("week"),
      .customLong("sync-week"),
    ],
    help: "Sync the current week only, from it's first day to it's last one, instead of --days"
  )
  var weekOnly = false

  func run() async throws {
    let window = try weekOnly ? currentWeek() : upcoming(days: days)
    let calendarService = CalendarServiceImpl()
    try await calendarService.requestAccess()

    let syncService = SyncService(calendarService: calendarService)
    let sources =
      from
      .flatMap { $0.split(separator: ",") }
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    var created = [CalendarEvent]()
    var deleted = [CalendarEvent]()
    var updated = [CalendarEvent]()

    for source in sources {
      print("Syncing events from '\(source)' to '\(to)' within \(window.label)")
      let result = try await syncService.sync(from: source, to: to, within: window.interval)
      created.append(contentsOf: result.createdEvents)
      deleted.append(contentsOf: result.deletedEvents)
      updated.append(contentsOf: result.updatedEvents)
    }

    let details =
      if created.isEmpty && updated.isEmpty && deleted.isEmpty {
        "no changes"
      } else {
        "\(created.count) created, \(updated.count) updated, \(deleted.count) deleted"
      }
    print("Sync completed, \(details)")
    printDiff(created: created, updated: updated, deleted: deleted)
  }

  private func printDiff(
    created: [CalendarEvent],
    updated: [CalendarEvent],
    deleted: [CalendarEvent],
  ) {
    let changes =
      created.map { (Change.created, $0) } + updated.map { (Change.modified, $0) }
      + deleted.map { (Change.deleted, $0) }
    guard !changes.isEmpty else { return }

    let useColor = isatty(STDOUT_FILENO) != 0
    let reset = "\u{1B}[0m"

    print()
    for (change, event) in changes.sorted(by: { $0.1.startDate < $1.1.startDate }) {
      let line = "[\(change.rawValue)] \(stringify(event))"
      print(useColor ? "\(change.color)\(line)\(reset)" : line)
    }
  }

  private func stringify(_ event: CalendarEvent) -> String {
    let day = format(event.startDate, as: "yyyy-MM-dd")
    guard !event.isAllDay else { return "\(event.title), \(day) all day" }

    let start = format(event.startDate, as: "HH:mm")
    let sameDay = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)
    let end = format(event.endDate, as: sameDay ? "HH:mm" : "yyyy-MM-dd HH:mm")
    return "\(event.title), \(day) \(start) - \(end)"
  }

  private enum Change: String {
    case created = "c"
    case modified = "m"
    case deleted = "d"

    var color: String {
      switch self {
      case .created: return "\u{1B}[32m"
      case .modified: return "\u{1B}[33m"
      case .deleted: return "\u{1B}[31m"
      }
    }
  }

  private struct SyncWindow {
    let interval: DateInterval
    let label: String
  }

  private func upcoming(days: Int) throws -> SyncWindow {
    guard days > 0 else {
      throw ValidationError("--days must be greater than zero")
    }

    let calendar = Calendar.current
    let start = calendar.startOfDay(for: Date())
    guard let end = calendar.date(byAdding: .day, value: days, to: start) else {
      throw CalendarService.Error.validationError(
        "Couldn't build a \(days)-day interval from \(start)"
      )
    }

    let lastInstant = end.addingTimeInterval(-1)
    return SyncWindow(
      interval: DateInterval(start: start, end: end),
      label: "for \(days) day\(days == 1 ? "" : "s"): [\(range(start, lastInstant))]"
    )
  }

  private func currentWeek() throws -> SyncWindow {
    let calendar = Calendar.current
    guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
      throw CalendarService.Error.validationError("Could not determine current week")
    }

    let lastInstant = interval.end.addingTimeInterval(-1)
    return SyncWindow(
      interval: interval,
      label: "for the current week: [\(range(interval.start, lastInstant))]"
    )
  }

  private func range(_ start: Date, _ end: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    return "\(format(start)) - \(format(end))"
  }

  private func format(_ date: Date, as pattern: String = "yyyy-MM-dd HH:mm") -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }
}
