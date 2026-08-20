import Foundation
import ArgumentParser

struct ListCommand : AsyncParsableCommand { 
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List all available calendars"
  )

  func run() async throws {
    let service =  CalendarService()
    try await service.requestAccess()

    let calendars = service.calendars()
    if calendars.isEmpty {
      print("No calendars found")
      return
    }

    print("Available calendars:")
    for info in calendars {
      print(" - \(info.title); \(info.source) (\(info.sourceType)); id: \(info.id)")
    }
    print()
  }
}
