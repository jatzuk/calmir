import Foundation

protocol CalendarEventService {
  func resolveCalendar(_ reference: String) throws -> CalendarInfo
  func fetchEvents(from calendarID: String, within interval: DateInterval) async throws
    -> [CalendarEvent]
  func createEvent(
    _ event: CalendarEvent, in calendarID: String, from sourceID: String
  ) async throws
  func updateEvent(
    id identifier: String, with event: CalendarEvent, from sourceID: String
  ) async throws
  func deleteEvent(id identifier: String) async throws
}

final class SyncService {
  private let calendarService: any CalendarEventService

  init(calendarService: any CalendarEventService) {
    self.calendarService = calendarService
  }

  func sync(
    from source: String,
    to destination: String,
    within interval: DateInterval
  ) async throws -> Result {
    let sourceCalendar = try calendarService.resolveCalendar(source)
    let destinationCalendar = try calendarService.resolveCalendar(destination)
    guard sourceCalendar.id != destinationCalendar.id else {
      throw CalendarService.Error.validationError(
        "Source and destination resolve to the same calendar: \(sourceCalendar.title)"
      )
    }

    let sourceEvents = try await calendarService.fetchEvents(
      from: sourceCalendar.id, within: interval
    )
    let destinationEvents = try await calendarService.fetchEvents(
      from: destinationCalendar.id, within: interval
    )

    let managedDestinationEvents = destinationEvents.filter {
      $0.syncMetadata?.sourceCalendarID == sourceCalendar.id
    }

    var lookup = [CalendarEventIdentity: CalendarEvent]()
    for event in managedDestinationEvents {
      guard let metadata = event.syncMetadata else { continue }
      lookup[metadata.sourceIdentity] = event
    }

    let sourceEventIdentities = Set(sourceEvents.map { $0.identity })
    var created = [CalendarEvent]()
    var deleted = [CalendarEvent]()
    var updated = [CalendarEvent]()

    for event in sourceEvents {
      if let existing = lookup[event.identity] {
        let needsUpdate =
          existing.title != event.title
          || !datesEqual(existing.startDate, event.startDate)
          || !datesEqual(existing.endDate, event.endDate)
          || existing.isAllDay != event.isAllDay

        if needsUpdate {
          try await calendarService.updateEvent(
            id: existing.id, with: event, from: sourceCalendar.id
          )
          updated.append(event)
        }
      } else {
        try await calendarService.createEvent(
          event, in: destinationCalendar.id, from: sourceCalendar.id
        )
        created.append(event)
      }
    }

    for event in managedDestinationEvents {
      guard let metadata = event.syncMetadata,
        !sourceEventIdentities.contains(metadata.sourceIdentity)
      else { continue }

      try await calendarService.deleteEvent(id: event.id)
      deleted.append(event)
    }

    return Result(
      source: source,
      destination: destination,
      createdEvents: created,
      deletedEvents: deleted,
      updatedEvents: updated
    )
  }

  private func datesEqual(_ lhs: Date, _ rhs: Date) -> Bool {
    let l60 = (lhs.timeIntervalSinceReferenceDate / 60).rounded(.towardZero)
    let r60 = (rhs.timeIntervalSinceReferenceDate / 60).rounded(.towardZero)
    return l60 == r60
  }

  struct Result {
    let source: String
    let destination: String

    let createdEvents: [CalendarEvent]
    let deletedEvents: [CalendarEvent]
    let updatedEvents: [CalendarEvent]

    var eventCount: Int {
      return createdEvents.count + deletedEvents.count + updatedEvents.count
    }
  }
}
