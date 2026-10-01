import EventKit
import Foundation

final class CalendarServiceImpl: CalendarService {
  private let eventStore = EKEventStore()
  private let syncMetadataCodec = EventSyncMetadataCodec()
  private let syncExclusionMarker = EventSyncExclusionMarker()


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
    from calendarId: String,
    within interval: DateInterval
  ) async throws -> [CalendarEvent] {
    guard
      let calendar = eventStore.calendars(for: .event)
        .first(where: { $0.calendarIdentifier == calendarId })
    else {
      throw CalendarService.Error.calendarNotFound(
        "No calendar found with identifier \(calendarId)"
      )
    }

    let predicate = eventStore.predicateForEvents(
      withStart: interval.start, end: interval.end, calendars: [calendar]
    )

    return eventStore.events(matching: predicate)
      .sorted { $0.startDate < $1.startDate }
      .map { [syncMetadataCodec, syncExclusionMarker] event in
        CalendarEvent(
          id: event.eventIdentifier,
          // EventKit reports the start date as occurrenceDate for non-recurring events,
          // so keep it only where it's needed to tell recurring occurrences apart
          occurrenceDate: event.hasRecurrenceRules ? event.occurrenceDate : nil,
          title: event.title ?? "(No title)",
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: event.isAllDay,
          ignoresSync: syncExclusionMarker.isMarked(event.notes),
          syncMetadata: syncMetadataCodec.decode(from: event.notes)
        )
      }
  }

  func createEvent(
    _ event: CalendarEvent,
    in calendarId: String,
    from sourceId: String
  ) async throws {
    guard let calendar = findCalendar(id: calendarId) else {
      throw CalendarService.Error.calendarNotFound(calendarId)
    }

    let ekEvent = EKEvent(eventStore: eventStore)
    ekEvent.title = event.title
    ekEvent.startDate = event.startDate
    ekEvent.endDate = event.endDate
    ekEvent.isAllDay = event.isAllDay
    ekEvent.notes = syncMetadataCodec.encode(
      CalendarEvent.SyncMetadata(
        sourceCalendarId: sourceId,
        sourceEventId: event.id,
        sourceOccurrenceDate: event.occurrenceDate
      )
    )
    ekEvent.calendar = calendar

    do {
      try eventStore.save(ekEvent, span: .thisEvent)
    } catch {
      throw CalendarService.Error.eventCreateFailed(error.localizedDescription)
    }
  }

  func updateEvent(
    id identifier: String,
    with event: CalendarEvent,
    from sourceId: String
  ) async throws {
    guard let ekEvent = eventStore.event(withIdentifier: identifier) else {
      throw CalendarService.Error.eventUpdateFailed("Event not found for identifier: \(identifier)")
    }
    ekEvent.title = event.title
    ekEvent.startDate = event.startDate
    ekEvent.endDate = event.endDate
    ekEvent.isAllDay = event.isAllDay
    ekEvent.notes = syncMetadataCodec.encode(
      CalendarEvent.SyncMetadata(
        sourceCalendarId: sourceId,
        sourceEventId: event.id,
        sourceOccurrenceDate: event.occurrenceDate
      )
    )

    do {
      try eventStore.save(ekEvent, span: .thisEvent)
    } catch {
      throw CalendarService.Error.eventUpdateFailed(error.localizedDescription)
    }
  }

  func deleteEvent(id identifier: String) async throws {
    guard let ekEvent = eventStore.event(withIdentifier: identifier) else {
      throw CalendarService.Error.eventDeleteFailed("Event not found for identifier: \(identifier)")
    }
    do {
      try eventStore.remove(ekEvent, span: .thisEvent)
    } catch {
      throw CalendarService.Error.eventDeleteFailed(error.localizedDescription)
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
