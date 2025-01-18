#!/usr/bin/env swift sh

//
// This script will set up development environment. Much wow.
//

import Foundation

import ArgumentParser // apple/swift-argument-parser ~> 1.0.0

enum ScriptError: Error {
    case parseError(String)
    case runCommandFail(String)
}

struct EnvironmentScript: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "environment.swift",
        abstract: "This script will set up the development environment by downloading all dependencies and generating all code."
    )

    @Argument(help: "Your API ID from https://my.telegram.org/")
    var apiId: Int?

    @Argument(help: "Your API hash from https://my.telegram.org/")
    var apiHash: String?

    func run() throws {
        if let apiId, let apiHash {
            log("Installing dependencies...")
            try install(command: "gyb", from: "ggoraa/apps/gyb", as: "GYB")
            log("Running GYB...")
            try run(command: "./gyb.sh", with: [String(apiId), apiHash])
            log("Finished environment setup!")
        } else {
            log("Please, provide <api_id> and <api_hash> arguments, obtained at https://my.telegram.org/")
        }
    }

    func log(_ message: String) {
        print(">>> " + message)
    }

    /// Installs a specified command if not available
    /// - Parameters:
    ///   - command: Command to be installed
    ///   - brew: Name of the command in Homebrew
    ///   - display: How this command's name is displayed in logs
    func install(command: String, from brew: String, as display: String) throws {
        if try runWithOutput(command: "which", with: [command]).contains(command) {
            log("\(display) is installed")
        } else {
            log("\(display) was not found, installing...")
            print("\n--- Homebrew output ---\n")
            try run(command: "brew", with: ["install", brew])
            print("\n------\n")
        }
    }

    /// Runs a supplied shell command.
    /// - Parameters:
    ///   - command: A command to run.
    ///   - args: Args supplied to it
    /// - Throws: Any error, like being unable to parse command's response or a run failure.
    /// - Returns: Command's output
    @discardableResult
    func run(command: String, with args: [String]) throws -> Int32 {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = [command] + args
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }

    /// Runs a supplied shell command.
    /// - Parameters:
    ///   - command: A command to run.
    ///   - args: Args supplied to it
    /// - Throws: Any error, like being unable to parse command's response or a run failure.
    /// - Returns: Command's output
    @discardableResult
    func runWithOutput(command: String, with args: [String]) throws -> String {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = [command] + args

        var pipe = Pipe()
        which.standardOutput = pipe

        do {
            try which.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output
            } else {
                throw ScriptError.parseError("Unable to parse '\(command)' command's output")
            }
        } catch {
            throw ScriptError.runCommandFail("Unable to run command \(command)")
        }
    }
}

EnvironmentScript.main()
