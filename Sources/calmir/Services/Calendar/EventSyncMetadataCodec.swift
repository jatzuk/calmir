import Foundation

struct EventSyncMetadataCodec {
  private let currentPrefix = "[calmir-sync:v2:"
  private let legacyPrefix = "[calmir-sync:v1:"

  func encode(_ metadata: CalendarEvent.SyncMetadata) -> String {
    let occurrence =
      metadata.sourceOccurrenceDate.map {
        String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
      } ?? ""
    let calendarId = encode(metadata.sourceCalendarId)
    let eventId = encode(metadata.sourceEventId)
    return "\(currentPrefix)\(calendarId):\(eventId):\(occurrence)]"
  }

  func decode(from notes: String?) -> CalendarEvent.SyncMetadata? {
    guard let notes else { return nil }
    if notes.hasPrefix(currentPrefix) {
      return decodeCurrent(from: notes)
    }
    if notes.hasPrefix(legacyPrefix) {
      return decodeLegacy(from: notes)
    }
    return nil
  }

  private func decodeCurrent(from notes: String) -> CalendarEvent.SyncMetadata? {
    guard let end = notes.firstIndex(of: "]") else {
      return nil
    }

    let payloadStart = notes.index(notes.startIndex, offsetBy: currentPrefix.count)
    let components = notes[payloadStart..<end].split(
      separator: ":", maxSplits: 2, omittingEmptySubsequences: false
    )
    guard components.count == 3,
      let sourceCalendarId = decode(components[0]),
      let sourceEventId = decode(components[1])
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

    return CalendarEvent.SyncMetadata(
      sourceCalendarId: sourceCalendarId,
      sourceEventId: sourceEventId,
      sourceOccurrenceDate: sourceOccurrenceDate
    )
  }

  private func decodeLegacy(from notes: String) -> CalendarEvent.SyncMetadata? {
    guard let end = notes.firstIndex(of: "]") else { return nil }

    let payloadStart = notes.index(notes.startIndex, offsetBy: legacyPrefix.count)
    let components = notes[payloadStart..<end].split(
      separator: ":", maxSplits: 1, omittingEmptySubsequences: false
    )
    guard components.count == 2,
      let sourceCalendarId = decode(components[0]),
      let sourceEventId = decode(components[1])
    else {
      return nil
    }

    return CalendarEvent.SyncMetadata(sourceCalendarId: sourceCalendarId, sourceEventId: sourceEventId)
  }

  private func encode(_ value: String) -> String {
    return Data(value.utf8).base64EncodedString()
  }

  private func decode(_ value: Substring) -> String? {
    guard let data = Data(base64Encoded: String(value)) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
