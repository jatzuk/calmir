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
  let syncMetadata: SyncMetadata?

  var identity: Identity {
    return Identity(id: id, occurrenceDate: occurrenceDate)
  }

  struct Identity: Hashable {
    let id: String
    let occurrenceDate: Date?
  }

  struct SyncMetadata: Equatable {
    let sourceCalendarId: String
    let sourceEventId: String
    let sourceOccurrenceDate: Date?

    init(
      sourceCalendarId: String,
      sourceEventId: String,
      sourceOccurrenceDate: Date? = nil
    ) {
      self.sourceCalendarId = sourceCalendarId
      self.sourceEventId = sourceEventId
      self.sourceOccurrenceDate = sourceOccurrenceDate
    }

    var sourceIdentity: CalendarEvent.Identity {
      return CalendarEvent.Identity(
        id: sourceEventId,
        occurrenceDate: sourceOccurrenceDate
      )
    }
  }
}
