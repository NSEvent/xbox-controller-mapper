			do {
				try process.run()
			} catch {
				return .failure("\(name) launch failed: \(error.localizedDescription)")
			}

			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			process.waitUntilExit()

			let output = String(data: data, encoding: .utf8)?
				.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

			if process.terminationStatus == 0 {
				return .success(success)
			}
			return .failure(output.isEmpty ? "\(name) exit \(process.terminationStatus)" : output)
