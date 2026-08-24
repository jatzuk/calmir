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

  #expect(calendarService.fetchedCalendarIds.isEmpty)
  #expect(calendarService.created.isEmpty)
  #expect(calendarService.updated.isEmpty)
  #expect(calendarService.deletedIds.isEmpty)
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
  #expect(calendarService.deletedIds.isEmpty)
  #expect(result.createdEvents.map(\.id) == ["source-1"])
}

@Test
func matchesRepeatedTitlesBySourceEventId() async throws {
  let firstSource = makeEvent(id: "source-1", title: "Focus", startMinute: 10)
  let secondSource = makeEvent(id: "source-2", title: "Focus", startMinute: 20)
  let firstDestination = makeEvent(
    id: "destination-1",
    title: "Focus",
    startMinute: 10,
    syncMetadata: metadata(eventId: "source-1")
  )
  let secondDestination = makeEvent(
    id: "destination-2",
    title: "Focus",
    startMinute: 20,
    syncMetadata: metadata(eventId: "source-2")
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
  #expect(calendarService.deletedIds.isEmpty)
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
    syncMetadata: metadata(eventId: "series-1", occurrenceMinute: 10)
  )
  let secondDestination = makeEvent(
    id: "destination-2",
    title: "Daily focus",
    startMinute: 20,
    syncMetadata: metadata(eventId: "series-1", occurrenceMinute: 20)
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
  #expect(calendarService.deletedIds.isEmpty)
  #expect(result.eventCount == 0)
}

@Test
func deletesOnlyTheMissingRepeatedTitleOccurrence() async throws {
  let remainingSource = makeEvent(id: "source-1", title: "Focus", startMinute: 10)
  let remainingDestination = makeEvent(
    id: "destination-1",
    title: "Focus",
    startMinute: 10,
    syncMetadata: metadata(eventId: "source-1")
  )
  let removedDestination = makeEvent(
    id: "destination-2",
    title: "Focus",
    startMinute: 20,
    syncMetadata: metadata(eventId: "source-2")
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [remainingSource],
    "Destination": [remainingDestination, removedDestination],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.deletedIds == ["destination-2"])
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
    syncMetadata: metadata(eventId: "series-1", occurrenceMinute: 10)
  )
  let removedDestination = makeEvent(
    id: "destination-2",
    title: "Daily focus",
    startMinute: 20,
    syncMetadata: metadata(eventId: "series-1", occurrenceMinute: 20)
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [remainingSource],
    "Destination": [remainingDestination, removedDestination],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.deletedIds == ["destination-2"])
  #expect(result.deletedEvents.map(\.id) == ["destination-2"])
}

@Test
func updatesTheTitleOfAnIdentifiedEvent() async throws {
  let sourceEvent = makeEvent(id: "source-1", title: "New title", startMinute: 10)
  let destinationEvent = makeEvent(
    id: "destination-1",
    title: "Old title",
    startMinute: 10,
    syncMetadata: metadata(eventId: "source-1")
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [sourceEvent],
    "Destination": [destinationEvent],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.updated.map(\.destinationId) == ["destination-1"])
  #expect(calendarService.updated.map(\.event.title) == ["New title"])
  #expect(result.updatedEvents.map(\.id) == ["source-1"])
}

@Test
func skipsSourceEventsMarkedNoSync() async throws {
  let syncedEvent = makeEvent(id: "source-1", title: "Standup", startMinute: 10)
  let privateEvent = makeEvent(
    id: "source-2", title: "Therapy", startMinute: 20, ignoresSync: true
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [syncedEvent, privateEvent],
    "Destination": [],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.created.map(\.event.id) == ["source-1"])
  #expect(calendarService.updated.isEmpty)
  #expect(calendarService.deletedIds.isEmpty)
  #expect(result.createdEvents.map(\.id) == ["source-1"])
}

@Test
func removesTheMirrorWhenASourceEventBecomesNoSync() async throws {
  let privateEvent = makeEvent(
    id: "source-1", title: "Therapy", startMinute: 10, ignoresSync: true
  )
  let staleMirror = makeEvent(
    id: "destination-1",
    title: "Therapy",
    startMinute: 10,
    syncMetadata: metadata(eventId: "source-1")
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [privateEvent],
    "Destination": [staleMirror],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.created.isEmpty)
  #expect(calendarService.updated.isEmpty)
  #expect(calendarService.deletedIds == ["destination-1"])
  #expect(result.deletedEvents.map(\.id) == ["destination-1"])
}

@Test
func leavesDestinationEventsMarkedNoSyncUntouched() async throws {
  let sourceEvent = makeEvent(id: "source-1", title: "New title", startMinute: 10)
  let pinnedMirror = makeEvent(
    id: "destination-1",
    title: "Old title",
    startMinute: 10,
    ignoresSync: true,
    syncMetadata: metadata(eventId: "source-1")
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [sourceEvent],
    "Destination": [pinnedMirror],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.created.isEmpty)
  #expect(calendarService.updated.isEmpty)
  #expect(calendarService.deletedIds.isEmpty)
  #expect(result.eventCount == 0)
}

@Test
func keepsDeletingOtherMirrorsWhileANoSyncMirrorSurvives() async throws {
  let pinnedMirror = makeEvent(
    id: "destination-1",
    title: "Pinned",
    startMinute: 10,
    ignoresSync: true,
    syncMetadata: metadata(eventId: "source-1")
  )
  let staleMirror = makeEvent(
    id: "destination-2",
    title: "Stale",
    startMinute: 20,
    syncMetadata: metadata(eventId: "source-2")
  )
  let calendarService = FakeCalendarEventService(events: [
    "Source": [],
    "Destination": [pinnedMirror, staleMirror],
  ])

  let result = try await SyncService(calendarService: calendarService).sync(
    from: "Source", to: "Destination", within: testInterval
  )

  #expect(calendarService.deletedIds == ["destination-2"])
  #expect(result.deletedEvents.map(\.id) == ["destination-2"])
}

@Test(arguments: [
  "nosync",
  "NoSync",
  "Team offsite #NOSYNC",
  "keep this private, nosync please",
])
func detectsTheNoSyncMarkerAnywhereInTheDescription(notes: String) {
  #expect(EventSyncExclusionMarker().isMarked(notes))
}

@Test(arguments: [nil, "", "Weekly review", "sync with the team", "no sync"])
func treatsDescriptionsWithoutTheMarkerAsSyncable(notes: String?) {
  #expect(!EventSyncExclusionMarker().isMarked(notes))
}

@Test
func syncMetadataTagRoundTripsArbitraryIdentifiers() {
  let metadata = CalendarEvent.SyncMetadata(
    sourceCalendarId: "Work: EMEA [shared] 🌍",
    sourceEventId: "event/123:=[]",
    sourceOccurrenceDate: testInterval.start.addingTimeInterval(10 * 60)
  )
  let codec = EventSyncMetadataCodec()

  #expect(codec.decode(from: codec.encode(metadata)) == metadata)
}

@Test
func syncMetadataCodecDecodesLegacyNonRecurringTag() {
  let calendarId = Data("source-id".utf8).base64EncodedString()
  let eventId = Data("event-id".utf8).base64EncodedString()
  let legacyTag = "[calmir-sync:v1:\(calendarId):\(eventId)]"

  #expect(
    EventSyncMetadataCodec().decode(from: legacyTag)
      == CalendarEvent.SyncMetadata(sourceCalendarId: "source-id", sourceEventId: "event-id")
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

private func metadata(eventId: String, occurrenceMinute: Int? = nil) -> CalendarEvent.SyncMetadata {
  return CalendarEvent.SyncMetadata(
    sourceCalendarId: "source-id",
    sourceEventId: eventId,
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
  ignoresSync: Bool = false,
  syncMetadata: CalendarEvent.SyncMetadata? = nil
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
    ignoresSync: ignoresSync,
    syncMetadata: syncMetadata
  )
}

private final class FakeCalendarEventService: CalendarService {
  struct Creation {
    let event: CalendarEvent
    let destination: String
    let source: String
  }

  struct Update {
    let destinationId: String
    let event: CalendarEvent
    let source: String
  }

  private let events: [String: [CalendarEvent]]
  private let calendars: [CalendarInfo]
  private(set) var created = [Creation]()
  private(set) var updated = [Update]()
  private(set) var deletedIds = [String]()
  private(set) var fetchedCalendarIds = [String]()

  init(events: [String: [CalendarEvent]]) {
    var eventsById = [String: [CalendarEvent]]()
    var calendars = [CalendarInfo]()
    for (title, calendarEvents) in events {
      let id = "\(title.lowercased())-id"
      eventsById[id] = calendarEvents
      calendars.append(CalendarInfo(id: id, title: title, source: "Test", sourceType: "Local"))
    }
    self.events = eventsById
    self.calendars = calendars
  }

  func resolveCalendar(_ reference: String) throws -> CalendarInfo {
    if let exactMatch = calendars.first(where: { $0.id == reference }) {
      return exactMatch
    }
    return try #require(calendars.first(where: { $0.title == reference }))
  }

  func fetchEvents(from calendarId: String, within interval: DateInterval) async throws
    -> [CalendarEvent]
  {
    fetchedCalendarIds.append(calendarId)
    return events[calendarId, default: []]
  }

  func createEvent(
    _ event: CalendarEvent,
    in calendarId: String,
    from sourceId: String
  ) async throws {
    created.append(Creation(event: event, destination: calendarId, source: sourceId))
  }

  func updateEvent(
    id identifier: String,
    with event: CalendarEvent,
    from sourceId: String
  ) async throws {
    updated.append(Update(destinationId: identifier, event: event, source: sourceId))
  }

  func deleteEvent(id identifier: String) async throws {
    deletedIds.append(identifier)
  }
}
