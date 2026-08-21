import Foundation

protocol CalendarService {

  /// help Swift support nested declarations in protocols
  typealias Error = CalendarServiceError

  func resolveCalendar(_ reference: String) throws -> CalendarInfo

  func fetchEvents(
    from calendarId: String,
    within interval: DateInterval
  ) async throws -> [CalendarEvent]

  func createEvent(
    _ event: CalendarEvent,
    in calendarId: String,
    from sourceId: String
  ) async throws

  func updateEvent(
    id identifier: String,
    with event: CalendarEvent,
    from sourceId: String
  ) async throws

  func deleteEvent(id identifier: String) async throws
}

enum CalendarServiceError: Swift.Error {
  case noPermission

  case validationError(String)
  case calendarNotFound(String)
  case ambiguousCalendar(String)

  case eventCreateFailed(String)
  case eventUpdateFailed(String)
  case eventDeleteFailed(String)
}
