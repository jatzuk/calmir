import Foundation

struct EventSyncExclusionMarker {
  static let token = "nosync"

  func isMarked(_ notes: String?) -> Bool {
    guard let notes else { return false }
    return notes.range(of: Self.token, options: .caseInsensitive) != nil
  }
}
