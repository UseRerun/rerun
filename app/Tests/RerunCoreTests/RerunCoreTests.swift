import Testing
@testable import RerunCore

@Test func versionIsSet() {
    #expect(Rerun.version == "0.2.0")
    #expect(Rerun.name == "Rerun")
}
