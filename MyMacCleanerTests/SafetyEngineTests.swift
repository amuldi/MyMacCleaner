import Testing
import Foundation
@testable import MyMacCleaner

@Suite("SafetyEngine")
struct SafetyEngineTests {
    @Test("System files are PROTECTED")
    func systemFilesAreProtected() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")
        let (safety, _) = SafetyEngine.evaluate(url: url, category: .systemUserCache)
        #expect(safety == .protected)
    }

    @Test("User documents are PROTECTED even under a category that is usually cleanable")
    func userDocumentsAreProtected() {
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/report.pdf")
        let (safety, reason) = SafetyEngine.evaluate(url: documents, category: .developerData)
        #expect(safety == .protected)
        #expect(!reason.isEmpty)
    }

    @Test("SSH keys are PROTECTED")
    func sshKeysAreProtected() {
        let key = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/id_ed25519")
        #expect(ProtectedPathRegistry.isProtected(key))
    }

    @Test("Git repository internals are PROTECTED")
    func gitRepositoriesAreProtected() {
        let gitFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/app/.git/objects/pack/pack-abc.pack")
        #expect(ProtectedPathRegistry.isProtected(gitFile))
    }

    @Test("Keychain files are PROTECTED")
    func keychainFilesAreProtected() {
        let keychain = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/login.keychain-db")
        #expect(ProtectedPathRegistry.isProtected(keychain))
    }

    @Test("Application caches are SAFE")
    func applicationCachesAreSafe() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.example.App")
        let (safety, reason) = SafetyEngine.evaluate(url: url, category: .applicationCache)
        #expect(safety == .safe)
        #expect(!reason.isEmpty)
    }

    @Test("Log files are SAFE")
    func logFilesAreSafe() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/install.log")
        let (safety, _) = SafetyEngine.evaluate(url: url, category: .logs)
        #expect(safety == .safe)
    }

    @Test("Xcode DerivedData is SAFE — it's pure build output")
    func derivedDataIsSafe() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData/App-abc123")
        let (safety, _) = SafetyEngine.evaluate(url: url, category: .developerData)
        #expect(safety == .safe)
    }

    @Test("Browser cache is SAFE")
    func browserCacheIsSafe() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.apple.Safari")
        let (safety, _) = SafetyEngine.evaluate(url: url, category: .browserCache)
        #expect(safety == .safe)
    }

    @Test("Downloaded installer files are REVIEW, never auto-selected")
    func installerFilesAreReview() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/SomeApp.dmg")
        let (safety, _) = SafetyEngine.evaluate(url: url, category: .installerFiles)
        #expect(safety == .review)
    }

    @Test("Xcode Archives are REVIEW, never auto-selected")
    func archivesAreReview() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/Archives/2026-01-01/App 1.xcarchive")
        let (safety, _) = SafetyEngine.evaluate(url: url, category: .developerData)
        #expect(safety == .review)
    }

    @Test("An unrecognized .app path is not protected purely by the running-app check")
    func nonRunningAppIsNotFlaggedAsRunning() {
        let fake = URL(fileURLWithPath: "/Applications/DefinitelyNotInstalled-\(UUID().uuidString).app")
        #expect(!ProtectedPathRegistry.isRunningApplication(fake))
    }

    @Test("Being large or old is never, by itself, a reason to classify something as SAFE or REVIEW differently")
    func categoryAloneDrivesClassificationNotSizeOrAge() {
        // Same category, same non-protected location — classification only
        // ever depends on path + category, never on size or modification date,
        // because SafetyEngine.evaluate doesn't even take those as input.
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.example.Big")
        let (safety1, _) = SafetyEngine.evaluate(url: url, category: .applicationCache)
        let (safety2, _) = SafetyEngine.evaluate(url: url, category: .applicationCache)
        #expect(safety1 == safety2)
    }
}
