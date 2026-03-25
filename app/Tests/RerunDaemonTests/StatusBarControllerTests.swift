import Foundation
import Testing
@testable import RerunDaemon

@Suite("StatusBarController")
struct StatusBarControllerTests {
    @Test func rerunFolderURLCreatesMissingDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rerun-statusbar-test-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("rerun", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(!FileManager.default.fileExists(atPath: folder.path))

        let createdURL = try StatusBarController.rerunFolderURL(baseURL: folder)

        var isDirectory: ObjCBool = false
        #expect(createdURL == folder)
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
