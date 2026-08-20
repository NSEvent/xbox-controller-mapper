import sys

file_path = "XboxControllerMapper/XboxControllerMapper/Services/Profile/StreamDeckProfileParser.swift"

with open(file_path, "r") as f:
    content = f.read()

search1 = """        try process.run()
        process.waitUntilExit()"""

replace1 = """        try process.run()
        process.waitUntilExit()""" # no pipe reading, so no change needed here

file_path_2 = "XboxControllerMapper/XboxControllerMapper/Services/Controller/ControllerService+SteamHID.swift"

with open(file_path_2, "r") as f:
    content = f.read()

search2 = """        do {
            try process.run()
            process.waitUntilExit()
        } catch {"""

replace2 = search2 # no pipe reading, no change needed

file_path_3 = "XboxControllerMapper/XboxControllerMapper/Services/Scripting/ScriptEngine.swift"

with open(file_path_3, "r") as f:
    content = f.read()

search3 = """                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()"""

# this is already correct.

print("Checked other files.")
