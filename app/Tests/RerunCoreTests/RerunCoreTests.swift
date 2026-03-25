import Testing
@testable import RerunCore

@Test func versionIsSet() {
    #expect(Rerun.version == "0.2.3")
    #expect(Rerun.name == "Rerun")
}
