// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser

@main
struct calmir: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calmir",
        abstract: "A cli tool to sync calendar events between calendars",
        version: "0.0.1",
        subcommands: [ListCommand.self, SyncCommand.self],
    )
}
