import Foundation

enum CommunityProfileSubmissionFiles {
	struct Packet {
		let directory: URL
		let profileURL: URL
		let guideURL: URL
	}

	static func write(_ submission: CommunityProfileSubmission, to downloads: URL,
		fileManager: FileManager = .default) throws -> Packet {
		let directory = downloads.appendingPathComponent("ControllerKeys Community", isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
		let profileURL = directory.appendingPathComponent(submission.filename)
		let guideURL = profileURL.deletingPathExtension().appendingPathExtension("md")
		try AtomicFileWriter.write(submission.json, to: profileURL)
		try AtomicFileWriter.write(Data(submission.guide.utf8), to: guideURL)
		try AtomicFileWriter.write(Data(submission.issueBody.utf8), to: directory.appendingPathComponent("Submission.txt"))
		return Packet(directory: directory, profileURL: profileURL, guideURL: guideURL)
	}
}
