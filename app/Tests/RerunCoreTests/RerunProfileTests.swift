import Foundation
import Testing
@testable import RerunCore

@Suite("RerunProfile")
struct RerunProfileTests {
    @Test func defaultsToDefaultProfile() {
        let profile = RerunProfile.current(arguments: ["rerun"], environment: [:])
        #expect(profile == "default")
    }

    @Test func environmentSetsProfile() {
        let profile = RerunProfile.current(arguments: ["rerun"], environment: ["RERUN_PROFILE": "Dev Build"])
        #expect(profile == "dev-build")
    }

    @Test func argumentOverridesEnvironment() {
        let profile = RerunProfile.current(
            arguments: ["rerun-daemon", "--profile", "qa"],
            environment: ["RERUN_PROFILE": "dev"]
        )
        #expect(profile == "qa")
    }

    @Test func profilePathsAreIsolated() {
        #expect(RerunProfile.homeDirectoryName(profile: "default") == "rerun")
        #expect(RerunProfile.homeDirectoryName(profile: "dev") == "rerun-dev")
        #expect(RerunProfile.appSupportDirectoryName(profile: "default") == "Rerun")
        #expect(RerunProfile.appSupportDirectoryName(profile: "dev") == "Rerun-dev")
    }

    @Test func appVariantsInferProfileFromBundleIdentity() {
        #expect(RerunProfile.inferredDefaultProfile(bundleIdentifier: "com.rerun.app", processName: nil) == "default")
        #expect(RerunProfile.inferredDefaultProfile(bundleIdentifier: "com.rerun.dev", processName: nil) == "dev")
        #expect(RerunProfile.inferredDefaultProfile(bundleIdentifier: nil, processName: "RerunDev") == "dev")
    }
}
