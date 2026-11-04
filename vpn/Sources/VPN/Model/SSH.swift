import Foundation

struct RemoteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Collects a process's output from a background thread and splits it into lines.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var all = Data()
    private var pending = Data()

    func append(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        all.append(chunk)
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }

    /// Whatever is left after the last newline.
    func finish() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        let line = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return line
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: all, as: UTF8.self)
    }
}

/// Runs commands on the server with the system's /usr/bin/ssh.
struct SSH {
    let profile: ServerProfile
    let password: String?

    static var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VPN", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The app keeps its own known_hosts so it never touches ~/.ssh.
    static var knownHosts: URL { supportDirectory.appendingPathComponent("known_hosts") }

    /// ssh asks this script for the password (SSH_ASKPASS), which reads it from the environment.
    private static func askpassScript() throws -> URL {
        let url = supportDirectory.appendingPathComponent("askpass.sh")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$VPN_SSH_PASSWORD\"\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    /// Runs `command` on the server and returns its standard output.
    /// `onLine` receives every output line (stdout and stderr) as it arrives, on a background thread.
    @discardableResult
    func run(_ command: String, input: Data? = nil,
             onLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
        var args = [
            "-p", String(profile.port),
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(Self.knownHosts.path)",
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=20",
            "-o", "LogLevel=ERROR",
        ]
        var env = ProcessInfo.processInfo.environment
        switch profile.auth {
        case .password:
            env["SSH_ASKPASS"] = try Self.askpassScript().path
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = env["DISPLAY"] ?? ":0"
            env["VPN_SSH_PASSWORD"] = password ?? ""
            args += ["-o", "PreferredAuthentications=password,keyboard-interactive",
                     "-o", "NumberOfPasswordPrompts=1"]
        case .key:
            args += ["-o", "BatchMode=yes"]
            if !profile.keyPath.isEmpty {
                args += ["-i", (profile.keyPath as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"]
            }
        }
        args += ["\(profile.user)@\(profile.host)", command]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        process.environment = env
        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        let out = OutputBuffer(), err = OutputBuffer()
        try process.run()

        let group = DispatchGroup()
        for (pipe, buffer) in [(outPipe, out), (errPipe, err)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = pipe.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    for line in buffer.append(chunk) { onLine?(line) }
                }
                if let last = buffer.finish() { onLine?(last) }
                group.leave()
            }
        }

        let writer = inPipe.fileHandleForWriting
        if let input {
            DispatchQueue.global(qos: .userInitiated).async {
                writer.write(input)
                try? writer.close()
            }
        } else {
            try? writer.close()
        }

        let status: Int32 = await withCheckedContinuation { continuation in
            group.notify(queue: .global(qos: .userInitiated)) {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }

        guard status == 0 else {
            throw RemoteError(message: explain(status: status, stderr: err.text))
        }
        return out.text
    }

    /// Turns ssh / sudo / script errors into a sentence a person can act on.
    private func explain(status: Int32, stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let scriptError = lines.last(where: { $0.hasPrefix("Error: ") }) {
            return String(scriptError.dropFirst("Error: ".count))
        }
        func has(_ text: String) -> Bool { stderr.localizedCaseInsensitiveContains(text) }
        if has("REMOTE HOST IDENTIFICATION HAS CHANGED") || has("Host key verification failed") {
            return "This server's identity changed since you last connected. If you rebuilt the server, choose Use a Different Server and connect again."
        }
        if has("Permission denied") {
            return profile.auth == .password
                ? "The server didn't accept that username and password."
                : "The server didn't accept your SSH key."
        }
        if has("Could not resolve hostname") { return "Couldn't find a server at \(profile.host)." }
        if has("Connection refused") { return "The server refused the connection. Check the SSH port." }
        if has("timed out") || has("No route to host") {
            return "The server didn't respond. Check the address and that the server is running."
        }
        if has("a password is required") || has("is not in the sudoers") || has("incorrect password") {
            return "User \(profile.user) can't run commands as administrator (sudo). Sign in as root, or as a user with sudo rights."
        }
        if let last = lines.last { return last }
        return "The command failed on the server (exit code \(status))."
    }
}
