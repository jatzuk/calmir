import Foundation

struct CalendarInfo {
  let id: String
  let title: String
  let source: String
  let sourceType: String
}

struct CalendarEvent {
  let id: String
  let occurrenceDate: Date?
  let title: String
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
  let syncMetadata: EventSyncMetadata?

  var identity: CalendarEventIdentity {
    return CalendarEventIdentity(eventID: id, occurrenceDate: occurrenceDate)
  }
}

struct CalendarEventIdentity: Hashable {
  let eventID: String
  let occurrenceDate: Date?
}

struct EventSyncMetadata: Equatable {
  let sourceCalendarID: String
  let sourceEventID: String
  let sourceOccurrenceDate: Date?

  init(
    sourceCalendarID: String,
    sourceEventID: String,
    sourceOccurrenceDate: Date? = nil
  ) {
    self.sourceCalendarID = sourceCalendarID
    self.sourceEventID = sourceEventID
    self.sourceOccurrenceDate = sourceOccurrenceDate
  }

  var sourceIdentity: CalendarEventIdentity {
    return CalendarEventIdentity(
      eventID: sourceEventID,
      occurrenceDate: sourceOccurrenceDate
    )
  }
}
