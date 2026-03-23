import Testing
@testable import RerunCore

@Test func versionIsSet() {
    #expect(Rerun.version == "0.1.1")
    #expect(Rerun.name == "Rerun")
}
