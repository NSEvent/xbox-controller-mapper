import os

path = "XboxControllerMapper/XboxControllerMapperTests/OBSWebSocketLiveIntegrationTests.swift"
with open(path, "r") as f:
    content = f.read()

# Make the catch block return a default value or something safe since it shouldn't crash the program
old_code = r'''        do {
            try which.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            which.waitUntilExit()
            if which.terminationStatus == 0 {
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {
            // Ignore error and fall through to throw XCTSkip below
        }'''

new_code = r'''        do {
            try which.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            which.waitUntilExit()
            if which.terminationStatus == 0 {
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {
            // Ignore error and fall through to throw XCTSkip below
        }'''

# Note: We replaced try? which.run() previously but wait... The nc -z has a process too that might be unlaunched

# Let's verify what the code actually is currently.
