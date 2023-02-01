#!/usr/bin/env swift sh
// swiftlint:disable all

//
// This script will set up development environment. Much wow.
//

import Foundation

import ArgumentParser // apple/swift-argument-parser ~> 1.0.0

enum ScriptError: Error {
    case parseError(String)
    case runCommandFail(String)
}

enum UserChoice {
    case yes
    case no
}

struct EnvironmentScript: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "environment.swift",
        abstract: "This script will set up the development environment by downloading all dependencies and generating all code."
    )

    @Argument(help: "Your API ID from my.telegram.org.")
    var apiId: Int?

    @Argument(help: "Your API hash from my.telegram.org.")
    var apiHash: String?

    func run() throws {
        if let apiId, let apiHash {
            log("Installing dependencies...")
            try install(command: "swiftlint", from: "swiftlint", as: "SwiftLint")
            try install(command: "gyb", from: "ggoraa/apps/gyb", as: "GYB")
            try install(command: "swiftgen", from: "swiftgen", as: "SwiftGen")

            log("Running GYB...")

            try FileManager.default.createDirectory(
                atPath: "Utilities/Sources/Utilities/Generated",
                withIntermediateDirectories: true)

            var gybArgs = [String(apiId), String(apiHash)]

            try run(command: "./gyb.sh", with: gybArgs)

            if let envValue = envValue(for: "FETCH_SPM") {
                if let value = Int(envValue) {
                    switch value {
                        case 1:
                            log("Fetch SPM dependencies up front: using env imported choice...")
                            try resolveDependencies()
                        case 0:
                            log("Fetch SPM dependencies up front: using env imported choice...")
                            log("Skipping...")
                        default:
                            log("Bad value for FETCH_SPM supplied: \(envValue). Should either be 1 or 0.")
                    }
                } else {
                    log("Bad value for FETCH_SPM supplied: \(envValue). Should be just a number.")
                }
            } else {
                if askForContinuation("Fetch SPM dependencies up front?") {
                    try resolveDependencies()
                } else {
                    log("Skipping...")
                }
            }
        } else {
            log("Not enough arguments supplied, please check if you did insert API ID and hash values.")
        }

        log("Finished environment setup!")
    }

    func resolveDependencies() throws {
        log("Resolving dependencies by running xcodebuild -resolvePackageDependencies...")
        sectionStart("xcodebuild" + " output")

        try run(command: "xcodebuild", with: ["-resolvePackageDependencies"])

        sectionEnd()
    }

    func envValue(for key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    func log(_ message: String) {
        print(">>> " + message)
    }

    func sectionStart(_ message: String) {
        print("\n" + "--- " + message + " ---" + "\n")
    }

    func sectionEnd() {
        print("\n------\n")
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
            sectionStart("Homebrew output")
            try run(command: "brew", with: ["install", brew])
            sectionEnd()
        }
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

    /// Runs a supplied shell command.
    /// - Parameters:
    ///   - command: A command to run.
    ///   - args: Args supplied to it
    /// - Throws: Any error, like being unable to parse command's response or a run failure.
    /// - Returns: Command's output
    @discardableResult
    func run(pwd: String? = nil, env: [String: String]? = nil, command: String, with args: [String]) throws -> Int32 {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = [command] + args
        if let env {
            task.environment = env
        }
        if let pwd {
            task.currentDirectoryURL = URL(string: pwd)!
        }
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }

    /// Runs `readLine()` that asks the user for `y` or `n` response.
    /// - Parameter message: The message with the request.
    /// - Parameter explicit: Whether to explicitly ask for `yes` or `no` response.
    /// - Returns: User's choice
    func askForContinuation(_ message: String, explicit: Bool = false, preferred: UserChoice = .yes) -> Bool {
        // This mess is just a system for lighting the choices in different ways
        print(
            message + " "
                + (explicit
                ? "(" + (preferred == .yes
                ? "yes"
                : "yes")
                + "/" + (preferred == .no
                ? "no"
                : "no") + ")"
                : "(" + (preferred == .yes
                ? "Y"
                : "Y") + "/"
                + (preferred == .no
                ? "n"
                : "n") + ")")
                + " ", terminator: "")

        if let result = readLine() {
            switch result.lowercased() {
                case "y":
                    if explicit {
                        print()
                        log("Please write a full answer:")
                        askForContinuation(message, explicit: explicit, preferred: preferred)
                    } else {
                        return true
                    }
                case "yes":
                    return true
                case "n":
                    if explicit {
                        log("Please write a full answer:")
                        askForContinuation(message, explicit: explicit, preferred: preferred)
                    } else {
                        return false
                    }
                case "no":
                    return false
                default:
                    log("Wrong response. Please try again:")
                    askForContinuation(message, explicit: explicit, preferred: preferred)
            }
        } else {
            log("Unable to ask for continuation.")
        }

        return false
    }
}

EnvironmentScript.main()
