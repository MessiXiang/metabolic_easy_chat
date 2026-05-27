//
//  WorkspaceTerminalService.swift
//  easy_chat
//
//  Created by GitHub Copilot on 2026/5/20.
//

import Foundation
import Darwin

final class WorkspaceTerminalService {
    struct RunningProcess {
        let process: Process
        let inputHandle: FileHandle
    }

    func environment(pathAdditions: String, home: String = NSHomeDirectory()) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = [pathAdditions, existingPath].filter { !$0.isEmpty }.joined(separator: ":")
        environment["HOME"] = home
        environment["TMPDIR"] = FileManager.default.temporaryDirectory.path
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["LC_ALL"] = environment["LC_ALL"] ?? "en_US.UTF-8"
        return environment
    }

    func resolve(command: String, args: [String], environment: [String: String]) -> ResolvedTerminalCommand {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCommand.contains("/") {
            return ResolvedTerminalCommand(executable: trimmedCommand, args: args, displayCommand: display([trimmedCommand] + args))
        }
        if let executable = findExecutable(named: trimmedCommand, environment: environment) {
            return ResolvedTerminalCommand(executable: executable, args: args, displayCommand: display([executable] + args))
        }
        return ResolvedTerminalCommand(executable: trimmedCommand, args: args, displayCommand: display([trimmedCommand] + args))
    }

    func startInteractive(command: String, args: [String], workingDirectory: URL, environment: [String: String], onOutput: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws -> RunningProcess {
        let process = Process()
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw ChatError.builtinToolFailed("无法创建交互式终端。")
        }

        var attributes = termios()
        if tcgetattr(slaveFD, &attributes) == 0 {
            attributes.c_cc.3 = 0x7f
            _ = tcsetattr(slaveFD, TCSANOW, &attributes)
        }

        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle
        process.standardInput = slaveHandle
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = Self.text(from: data) else { return }
            onOutput(text)
        }
        process.terminationHandler = { terminated in
            masterHandle.readabilityHandler = nil
            onExit(terminated.terminationStatus)
        }
        do {
            try process.run()
            try? slaveHandle.close()
            return RunningProcess(process: process, inputHandle: masterHandle)
        } catch {
            masterHandle.readabilityHandler = nil
            try? masterHandle.close()
            try? slaveHandle.close()
            throw error
        }
    }

    func run(command: String, args: [String], workingDirectory: URL?, environment: [String: String], timeout: Int, onOutput: @escaping @Sendable (String) -> Void) async -> TerminalExecutionResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let resumeLock = NSLock()
            let output = LockedTextBuffer(limit: 40_000)
            var didResume = false

            @Sendable func snapshot(_ extra: String = "") -> String {
                output.snapshot(appending: extra)
            }

            @Sendable func append(_ text: String) {
                output.append(text)
                onOutput(text)
            }

            @Sendable func finish(status: ToolRunStatus, exitCode: Int32, extraOutput: String = "") {
                resumeLock.lock()
                guard !didResume else {
                    resumeLock.unlock()
                    return
                }
                didResume = true
                resumeLock.unlock()
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: TerminalExecutionResult(output: snapshot(extraOutput), status: status, exitCode: exitCode))
            }

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = Self.text(from: data) else { return }
                append(text)
            }

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = environment
            process.currentDirectoryURL = workingDirectory
            process.terminationHandler = { terminatedProcess in
                finish(status: terminatedProcess.terminationStatus == 0 ? .completed : .failed, exitCode: terminatedProcess.terminationStatus)
            }

            do {
                try process.run()
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                    if process.isRunning {
                        process.terminate()
                        finish(status: .failed, exitCode: -1, extraOutput: "\n[timeout after \(timeout)s]")
                    }
                }
            } catch {
                finish(status: .failed, exitCode: -1, extraOutput: error.localizedDescription)
            }
        }
    }

    private func findExecutable(named command: String, environment: [String: String]) -> String? {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in paths {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func display(_ parts: [String]) -> String {
        parts.map { value in
            value.contains(" ") ? "\"\(value)\"" : value
        }.joined(separator: " ")
    }

    private static func text(from data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

private final class LockedTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var text = ""

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ value: String) {
        lock.lock()
        text += value
        if text.count > limit {
            text = String(text.suffix(limit))
        }
        lock.unlock()
    }

    func snapshot(appending value: String = "") -> String {
        lock.lock()
        if !value.isEmpty {
            text += value
            if text.count > limit {
                text = String(text.suffix(limit))
            }
        }
        let current = text
        lock.unlock()
        return current
    }
}