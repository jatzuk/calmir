import Foundation
import Testing

@testable import calmir

@Test
func rejectsSyncingACalendarIntoItselfBeforeFetchingEvents() async {
  let calendarService = FakeCalendarEventService(events: [
    "Source": [makeEvent(id: "source-1", title: "Standup", startMinute: 10)]
  ])

  do {
    _ = try await SyncService(calendarService: calendarService).sync(
      from: "Source", to: "source-id", within: testInterval
    )
    Issue.record("Expected a same-calendar validation error")
  } catch CalendarService.Error.validationError(let message) {
    #expect(message.contains("same calendar"))
  } catch {
    Issue.record("Expected a validation error, got \(error)")
  }

  #expect(calendarService.fetchedCalendarIDs.isEmpty)
  #expect(calendarService.created.isEmpty)
  #expect(calendarService.updated.isEmpty)
  #expect(calendarService.deletedIDs.isEmpty)
}

@Test
func doesNotAdoptUntaggedDestinationEventWithTheSameTitle() async throws {
  let sourceEvent = makeEvent(id: "source-1", title: "Standup", startMinute: 10)
  let manualEvent = makeEvent(id: "manual-1", title: "Standup", startMinute: 10)
  let calendarService = FakeCalendarEventService(events: [
    "Source": [sourceEvent],
    "Destination": [manualEvent],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.created.map(\.event.id) == ["source-1"])
  #expect(calendarService.created.map(\.source) == ["source-id"])
  #expect(calendarService.created.map(\.destination) == ["destination-id"])
  #expect(calendarService.updated.isEmpty)
  #expect(calendarService.deletedIDs.isEmpty)
  #expect(result.createdEvents.map(\.id) == ["source-1"])
}

@Test
func matchesRepeatedTitlesBySourceEventID() async throws {
  let firstSource = makeEvent(id: "source-1", title: "Focus", startMinute: 10)
  let secondSource = makeEvent(id: "source-2", title: "Focus", startMinute: 20)
  let firstDestination = makeEvent(
    id: "destination-1",
    title: "Focus",
    startMinute: 10,
    syncMetadata: metadata(eventID: "source-1")
  )
  let secondDestination = makeEvent(
    id: "destination-2",
    title: "Focus",
    startMinute: 20,
    syncMetadata: metadata(eventID: "source-2")
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [firstSource, secondSource],
    "Destination": [firstDestination, secondDestination],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.created.isEmpty)
  #expect(calendarService.updated.isEmpty)
  #expect(calendarService.deletedIDs.isEmpty)
  #expect(result.eventCount == 0)
}

@Test
func matchesRecurringOccurrencesByOccurrenceDate() async throws {
  let firstSource = makeEvent(
    id: "series-1", title: "Daily focus", startMinute: 10, occurrenceMinute: 10
  )
  let secondSource = makeEvent(
    id: "series-1", title: "Daily focus", startMinute: 20, occurrenceMinute: 20
  )
  let firstDestination = makeEvent(
    id: "destination-1",
    title: "Daily focus",
    startMinute: 10,
    syncMetadata: metadata(eventID: "series-1", occurrenceMinute: 10)
  )
  let secondDestination = makeEvent(
    id: "destination-2",
    title: "Daily focus",
    startMinute: 20,
    syncMetadata: metadata(eventID: "series-1", occurrenceMinute: 20)
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [firstSource, secondSource],
    "Destination": [firstDestination, secondDestination],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.created.isEmpty)
  #expect(calendarService.updated.isEmpty)
  #expect(calendarService.deletedIDs.isEmpty)
  #expect(result.eventCount == 0)
}

@Test
func deletesOnlyTheMissingRepeatedTitleOccurrence() async throws {
  let remainingSource = makeEvent(id: "source-1", title: "Focus", startMinute: 10)
  let remainingDestination = makeEvent(
    id: "destination-1",
    title: "Focus",
    startMinute: 10,
    syncMetadata: metadata(eventID: "source-1")
  )
  let removedDestination = makeEvent(
    id: "destination-2",
    title: "Focus",
    startMinute: 20,
    syncMetadata: metadata(eventID: "source-2")
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [remainingSource],
    "Destination": [remainingDestination, removedDestination],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.deletedIDs == ["destination-2"])
  #expect(result.deletedEvents.map(\.id) == ["destination-2"])
}

@Test
func deletesOnlyTheMissingRecurringOccurrence() async throws {
  let remainingSource = makeEvent(
    id: "series-1", title: "Daily focus", startMinute: 10, occurrenceMinute: 10
  )
  let remainingDestination = makeEvent(
    id: "destination-1",
    title: "Daily focus",
    startMinute: 10,
    syncMetadata: metadata(eventID: "series-1", occurrenceMinute: 10)
  )
  let removedDestination = makeEvent(
    id: "destination-2",
    title: "Daily focus",
    startMinute: 20,
    syncMetadata: metadata(eventID: "series-1", occurrenceMinute: 20)
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [remainingSource],
    "Destination": [remainingDestination, removedDestination],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.deletedIDs == ["destination-2"])
  #expect(result.deletedEvents.map(\.id) == ["destination-2"])
}

@Test
func updatesTheTitleOfAnIdentifiedEvent() async throws {
  let sourceEvent = makeEvent(id: "source-1", title: "New title", startMinute: 10)
  let destinationEvent = makeEvent(
    id: "destination-1",
    title: "Old title",
    startMinute: 10,
    syncMetadata: metadata(eventID: "source-1")
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [sourceEvent],
    "Destination": [destinationEvent],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.updated.map(\.destinationID) == ["destination-1"])
  #expect(calendarService.updated.map(\.event.title) == ["New title"])
  #expect(result.updatedEvents.map(\.id) == ["source-1"])
}

@Test
func syncMetadataTagRoundTripsArbitraryIdentifiers() {
  let metadata = EventSyncMetadata(
    sourceCalendarID: "Work: EMEA [shared] 🌍",
    sourceEventID: "event/123:=[]",
    sourceOccurrenceDate: testInterval.start.addingTimeInterval(10 * 60)
  )
  let codec = EventSyncMetadataCodec()

  #expect(codec.decode(from: codec.encode(metadata)) == metadata)
}

@Test
func syncMetadataCodecDecodesLegacyNonRecurringTag() {
  let calendarID = Data("source-id".utf8).base64EncodedString()
  let eventID = Data("event-id".utf8).base64EncodedString()
  let legacyTag = "[calmir-sync:v1:\(calendarID):\(eventID)]"

  #expect(
    EventSyncMetadataCodec().decode(from: legacyTag)
      == EventSyncMetadata(sourceCalendarID: "source-id", sourceEventID: "event-id")
  )
}

@Test
func calendarReferenceResolverPrefersAnExactIdentifier() throws {
  let calendars = [
    makeCalendar(id: "calendar-1", title: "Work", source: "iCloud"),
    makeCalendar(id: "Work", title: "Personal", source: "Local"),
  ]

  let resolved = try CalendarReferenceResolver().resolve("Work", among: calendars)

  #expect(resolved.id == "Work")
  #expect(resolved.title == "Personal")
}

@Test
func calendarReferenceResolverRejectsAnAmbiguousTitle() {
  let calendars = [
    makeCalendar(id: "calendar-1", title: "Work", source: "iCloud"),
    makeCalendar(id: "calendar-2", title: "Work", source: "Google"),
  ]

  do {
    _ = try CalendarReferenceResolver().resolve("Work", among: calendars)
    Issue.record("Expected an ambiguous calendar error")
  } catch CalendarService.Error.ambiguousCalendar {
    // Expected.
  } catch {
    Issue.record("Expected an ambiguous calendar error, got \(error)")
  }
}

private let testInterval = DateInterval(
  start: Date(timeIntervalSinceReferenceDate: 0),
  duration: 60 * 60
)

private func metadata(eventID: String, occurrenceMinute: Int? = nil) -> EventSyncMetadata {
  return EventSyncMetadata(
    sourceCalendarID: "source-id",
    sourceEventID: eventID,
    sourceOccurrenceDate: occurrenceMinute.map {
      testInterval.start.addingTimeInterval(TimeInterval($0 * 60))
    }
  )
}

private func makeCalendar(id: String, title: String, source: String) -> CalendarInfo {
  return CalendarInfo(id: id, title: title, source: source, sourceType: "Test")
}

private func makeEvent(
  id: String,
  title: String,
  startMinute: Int,
  occurrenceMinute: Int? = nil,
  syncMetadata: EventSyncMetadata? = nil
) -> CalendarEvent {
  let start = testInterval.start.addingTimeInterval(TimeInterval(startMinute * 60))
  return CalendarEvent(
    id: id,
    occurrenceDate: occurrenceMinute.map {
      testInterval.start.addingTimeInterval(TimeInterval($0 * 60))
    },
    title: title,
    startDate: start,
    endDate: start.addingTimeInterval(30 * 60),
    isAllDay: false,
    syncMetadata: syncMetadata
  )
}

private final class FakeCalendarEventService: CalendarEventService {
  struct Creation {
    let event: CalendarEvent
    let destination: String
    let source: String
  }

  struct Update {
    let destinationID: String
    let event: CalendarEvent
    let source: String
  }

  private let events: [String: [CalendarEvent]]
  private let calendars: [CalendarInfo]
  private(set) var created = [Creation]()
  private(set) var updated = [Update]()
  private(set) var deletedIDs = [String]()
  private(set) var fetchedCalendarIDs = [String]()

  init(events: [String: [CalendarEvent]]) {
    var eventsByID = [String: [CalendarEvent]]()
    var calendars = [CalendarInfo]()
    for (title, calendarEvents) in events {
      let id = "\(title.lowercased())-id"
      eventsByID[id] = calendarEvents
      calendars.append(CalendarInfo(id: id, title: title, source: "Test", sourceType: "Local"))
    }
    self.events = eventsByID
    self.calendars = calendars
  }

  func resolveCalendar(_ reference: String) throws -> CalendarInfo {
    if let exactMatch = calendars.first(where: { $0.id == reference }) {
      return exactMatch
    }
    return try #require(calendars.first(where: { $0.title == reference }))
  }

  func fetchEvents(from calendarID: String, within interval: DateInterval) async throws
    -> [CalendarEvent]
  {
    fetchedCalendarIDs.append(calendarID)
    return events[calendarID, default: []]
  }

  func createEvent(
    _ event: CalendarEvent,
    in calendarID: String,
    from sourceID: String
  ) async throws {
    created.append(Creation(event: event, destination: calendarID, source: sourceID))
  }

  func updateEvent(
    id identifier: String,
    with event: CalendarEvent,
    from sourceID: String
  ) async throws {
    updated.append(Update(destinationID: identifier, event: event, source: sourceID))
  }

  func deleteEvent(id identifier: String) async throws {
    deletedIDs.append(identifier)
  }
}
