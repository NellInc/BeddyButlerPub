import Foundation
import XCTest

extension XCTestCase {
    /// Returns an empty defaults suite named `prefix.<UUID>` that is removed when the test ends.
    ///
    /// The suite is an absolute path in the temporary directory rather than a plain name. cfprefsd writes
    /// an empty plist for every domain a process touched when it exits, after any teardown could delete
    /// it, so plain names would still leave one file per test in ~/Library/Preferences.
    func makeIsolatedDefaults(prefix: String) -> UserDefaults {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeddyButlerTestDefaults", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferenceFile = directory.appendingPathComponent("\(prefix).\(UUID().uuidString).plist")
        let suiteName = preferenceFile.deletingPathExtension().path
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated user defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: preferenceFile)
        }
        return defaults
    }
}
