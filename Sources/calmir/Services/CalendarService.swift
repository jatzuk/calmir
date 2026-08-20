import EventKit
import Foundation

final class CalendarService: CalendarEventService {
  private let eventStore = EKEventStore()
  private let syncMetadataCodec = EventSyncMetadataCodec()

  func requestAccess() async throws {
    let hasPermission = try await eventStore.requestFullAccessToEvents()
    if !hasPermission {
      throw CalendarService.Error.noPermission
    }
  }

  func calendars() -> [CalendarInfo] {
    return eventStore.calendars(for: .event).map { calendar in
      CalendarInfo(
        id: calendar.calendarIdentifier,
        title: calendar.title,
        source: calendar.source.title,
        sourceType: calendar.source.sourceType.stringify(),
      )
    }
  }

  func resolveCalendar(_ reference: String) throws -> CalendarInfo {
    return try CalendarReferenceResolver().resolve(reference, among: calendars())
  }

  func fetchEvents(
    from calendarID: String,
    within interval: DateInterval
  ) async throws -> [CalendarEvent] {
    guard
      let calendar = eventStore.calendars(for: .event).first(where: {
        $0.calendarIdentifier == calendarID
      })
    else {
      throw CalendarService.Error.calendarNotFound(
        "No calendar found with identifier \(calendarID)"
      )
    }

    let predicate = eventStore.predicateForEvents(
      withStart: interval.start, end: interval.end, calendars: [calendar]
    )

    return eventStore.events(matching: predicate)
      .sorted { $0.startDate < $1.startDate }
      .map { [syncMetadataCodec] event in
        CalendarEvent(
          id: event.eventIdentifier,
          occurrenceDate: event.occurrenceDate,
          title: event.title ?? "(No title)",
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: event.isAllDay,
          syncMetadata: syncMetadataCodec.decode(from: event.notes)
        )
      }
  }

  func createEvent(
    _ event: CalendarEvent,
    in calendarID: String,
    from sourceID: String
  ) async throws {
    guard let calendar = findCalendar(id: calendarID) else {
      throw Error.calendarNotFound(calendarID)
    }

    let ekEvent = EKEvent(eventStore: eventStore)
    ekEvent.title = event.title
    ekEvent.startDate = event.startDate
    ekEvent.endDate = event.endDate
    ekEvent.isAllDay = event.isAllDay
    ekEvent.notes = syncMetadataCodec.encode(
      EventSyncMetadata(
        sourceCalendarID: sourceID,
        sourceEventID: event.id,
        sourceOccurrenceDate: event.occurrenceDate
      )
    )
    ekEvent.calendar = calendar

    do {
      try eventStore.save(ekEvent, span: .thisEvent)
    } catch {
      throw Error.eventCreationFailed(error.localizedDescription)
    }
  }

  func updateEvent(
    id identifier: String,
    with event: CalendarEvent,
    from sourceID: String
  ) async throws {
    guard let ekEvent = eventStore.event(withIdentifier: identifier) else {
      throw Error.eventUpdateFailed("Event not found for identifier: \(identifier)")
    }
    ekEvent.title = event.title
    ekEvent.startDate = event.startDate
    ekEvent.endDate = event.endDate
    ekEvent.isAllDay = event.isAllDay
    ekEvent.notes = syncMetadataCodec.encode(
      EventSyncMetadata(
        sourceCalendarID: sourceID,
        sourceEventID: event.id,
        sourceOccurrenceDate: event.occurrenceDate
      )
    )

    do {
      try eventStore.save(ekEvent, span: .thisEvent)
    } catch {
      throw Error.eventUpdateFailed(error.localizedDescription)
    }
  }

  func deleteEvent(id identifier: String) async throws {
    guard let ekEvent = eventStore.event(withIdentifier: identifier) else {
      throw Error.eventDeletionFailed("Event not found for identifier: \(identifier)")
    }
    do {
      try eventStore.remove(ekEvent, span: .thisEvent)
    } catch {
      throw Error.eventDeletionFailed(error.localizedDescription)
    }
  }

  private func findCalendar(id identifier: String) -> EKCalendar? {
    return eventStore.calendars(for: .event).first { $0.calendarIdentifier == identifier }
  }

  private func info(for calendar: EKCalendar) -> CalendarInfo {
    return CalendarInfo(
      id: calendar.calendarIdentifier,
      title: calendar.title,
      source: calendar.source.title,
      sourceType: calendar.source.sourceType.stringify()
    )
  }

  enum Error: Swift.Error {
    case noPermission
    case validationError(String)
    case calendarNotFound(String)
    case ambiguousCalendar(String)
    case eventCreationFailed(String)
    case eventUpdateFailed(String)
    case eventDeletionFailed(String)
  }
}

struct CalendarReferenceResolver {
  func resolve(_ reference: String, among calendars: [CalendarInfo]) throws -> CalendarInfo {
    if let exactMatch = calendars.first(where: { $0.id == reference }) {
      return exactMatch
    }

    let titleMatches = calendars.filter { $0.title == reference }
    guard !titleMatches.isEmpty else {
      throw CalendarService.Error.calendarNotFound(
        "No calendar found for name or identifier: \(reference)"
      )
    }
    guard titleMatches.count == 1, let calendar = titleMatches.first else {
      let candidates =
        titleMatches
        .map { "\($0.source)/\($0.title) [\($0.id)]" }
        .joined(separator: ", ")
      throw CalendarService.Error.ambiguousCalendar(
        "Multiple calendars are named '\(reference)'; use an identifier: \(candidates)"
      )
    }

    return calendar
  }
}

struct EventSyncMetadataCodec {
  private let currentPrefix = "[calmir-sync:v2:"
  private let legacyPrefix = "[calmir-sync:v1:"

  func encode(_ metadata: EventSyncMetadata) -> String {
    let occurrence =
      metadata.sourceOccurrenceDate.map {
        String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
      } ?? ""
    let calendarID = encode(metadata.sourceCalendarID)
    let eventID = encode(metadata.sourceEventID)
    return "\(currentPrefix)\(calendarID):\(eventID):\(occurrence)]"
  }

  func decode(from notes: String?) -> EventSyncMetadata? {
    guard let notes else { return nil }
    if notes.hasPrefix(currentPrefix) {
      return decodeCurrent(from: notes)
    }
    if notes.hasPrefix(legacyPrefix) {
      return decodeLegacy(from: notes)
    }
    return nil
  }

  private func decodeCurrent(from notes: String) -> EventSyncMetadata? {
    guard let end = notes.firstIndex(of: "]") else {
      return nil
    }

    let payloadStart = notes.index(notes.startIndex, offsetBy: currentPrefix.count)
    let components = notes[payloadStart..<end].split(
      separator: ":", maxSplits: 2, omittingEmptySubsequences: false
    )
    guard components.count == 3,
      let sourceCalendarID = decode(components[0]),
      let sourceEventID = decode(components[1])
    else {
      return nil
    }

    let sourceOccurrenceDate: Date?
    if components[2].isEmpty {
      sourceOccurrenceDate = nil
    } else {
      guard let bitPattern = UInt64(components[2], radix: 16) else { return nil }
      sourceOccurrenceDate = Date(
        timeIntervalSinceReferenceDate: Double(bitPattern: bitPattern)
      )
    }

    return EventSyncMetadata(
      sourceCalendarID: sourceCalendarID,
      sourceEventID: sourceEventID,
      sourceOccurrenceDate: sourceOccurrenceDate
    )
  }

  private func decodeLegacy(from notes: String) -> EventSyncMetadata? {
    guard let end = notes.firstIndex(of: "]") else { return nil }

    let payloadStart = notes.index(notes.startIndex, offsetBy: legacyPrefix.count)
    let components = notes[payloadStart..<end].split(
      separator: ":", maxSplits: 1, omittingEmptySubsequences: false
    )
    guard components.count == 2,
      let sourceCalendarID = decode(components[0]),
      let sourceEventID = decode(components[1])
    else {
      return nil
    }

    return EventSyncMetadata(sourceCalendarID: sourceCalendarID, sourceEventID: sourceEventID)
  }

  private func encode(_ value: String) -> String {
    return Data(value.utf8).base64EncodedString()
  }

  private func decode(_ value: Substring) -> String? {
    guard let data = Data(base64Encoded: String(value)) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

extension EKSourceType {
  fileprivate func stringify() -> String {
    switch self {
    case .local: return "Local"
    case .exchange: return "Exchange"
    case .calDAV: return "CalDAV"
    case .mobileMe: return "MobileMe"
    case .subscribed: return "Subscribed"
    case .birthdays: return "Birthdays"
    @unknown default: return "Unknown"
    }
  }
}
