import sys

file_path = "TriggerKit/Sources/TriggerKitRuntime/AutomationExecutor.swift"
with open(file_path, "r") as f:
    content = f.read()

# I will revert childPIDs back to what it was to see if the tests pass
search_2 = """\
		do {
			try pgrep.run()
		} catch {
			return []
		}
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		pgrep.waitUntilExit()"""

replace_2 = """\
		do {
			try pgrep.run()
			pgrep.waitUntilExit()
		} catch {
			return []
		}
		let data = pipe.fileHandleForReading.readDataToEndOfFile()"""

if search_2 in content:
    content = content.replace(search_2, replace_2)
    print("Reverted block 2 successfully.")

with open(file_path, "w") as f:
    f.write(content)
