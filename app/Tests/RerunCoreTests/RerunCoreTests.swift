import Testing
@testable import RerunCore

@Test func versionIsSet() {
    #expect(Rerun.version == "0.2.2")
    #expect(Rerun.name == "Rerun")
}
