import Foundation

/// Decides how safe it is to remove a discovered file or folder, and produces the
/// user-facing explanation shown in "Why can I remove this?".
///
/// Rules of thumb encoded here (see product spec §8-9, §18):
///  - A path under a protected root (system files, personal documents, keys,
///    running app bundles, ...) is always PROTECTED, no matter its category.
///  - Plain caches, logs and temp files are SAFE — apps recreate them on demand.
///  - Developer build output (DerivedData) is SAFE; archives and anything the
///    scanner can't fully vouch for is REVIEW so the user decides.
///  - Nothing is ever classified purely because it is "old" or "large".
enum SafetyEngine {
    static func evaluate(url: URL, category: CleanCategory, language: AppLanguage = .english) -> (SafetyLevel, String) {
        if ProtectedPathRegistry.isProtected(url) {
            return (.protected, protectedReason(for: url, language: language))
        }

        switch category {
        case .applicationCache:
            return (.safe, L(
                "This is an application cache. The app can recreate it the next time it needs it.",
                "앱 캐시 파일입니다. 앱이 필요할 때 다시 만들어내므로 삭제해도 안전합니다.",
                for: language
            ))

        case .browserCache:
            return (.safe, L(
                "This is a web browser cache. The browser rebuilds it automatically as you browse.",
                "웹 브라우저 캐시입니다. 브라우저를 사용하면 자동으로 다시 만들어집니다.",
                for: language
            ))

        case .systemUserCache:
            return (.safe, L(
                "This is a cache maintained by macOS or an app. It is rebuilt automatically as needed.",
                "macOS 또는 앱이 관리하는 캐시입니다. 필요할 때 자동으로 다시 생성됩니다.",
                for: language
            ))

        case .logs:
            return (.safe, L(
                "This is a diagnostic log file. Removing it does not affect how any application runs.",
                "진단용 로그 파일입니다. 삭제해도 다른 앱 실행에는 영향을 주지 않습니다.",
                for: language
            ))

        case .temporaryFiles:
            return (.safe, L(
                "This is a temporary file created by macOS or an app to hold short-lived data.",
                "macOS나 앱이 잠깐 사용하려고 만든 임시 파일입니다.",
                for: language
            ))

        case .developerData:
            return developerDataSafety(for: url, language: language)

        case .installerFiles:
            return (.review, L(
                "This is a downloaded installer (.dmg/.pkg). Safe to remove once the software inside is already installed.",
                "다운로드한 설치 파일(.dmg/.pkg)입니다. 안에 들어있는 소프트웨어를 이미 설치했다면 삭제해도 됩니다.",
                for: language
            ))

        case .trash:
            return (.safe, L(
                "This item is already in the Trash, waiting to be permanently deleted.",
                "이미 휴지통에 있는 항목으로, 완전 삭제를 기다리고 있습니다.",
                for: language
            ))
        }
    }

    private static func developerDataSafety(for url: URL, language: AppLanguage) -> (SafetyLevel, String) {
        let path = url.path
        if path.contains("/Developer/Xcode/DerivedData/") {
            return (.safe, L(
                "This is Xcode build output. Xcode regenerates it automatically the next time you build.",
                "Xcode 빌드 결과물입니다. 다음에 빌드하면 Xcode가 자동으로 다시 생성합니다.",
                for: language
            ))
        }
        if path.contains("/Developer/CoreSimulator/Caches/") {
            return (.safe, L(
                "This is Simulator runtime cache data. It is rebuilt automatically as needed.",
                "시뮬레이터 런타임 캐시 데이터입니다. 필요할 때 자동으로 다시 생성됩니다.",
                for: language
            ))
        }
        if path.contains("/Developer/Xcode/Archives/") {
            return (.review, L(
                "This is an Xcode archive (.xcarchive). Keep it if you may need to re-submit or symbolicate crash reports for this build.",
                "Xcode 아카이브(.xcarchive)입니다. 이 빌드를 다시 제출하거나 충돌 리포트를 분석할 일이 있다면 보관하세요.",
                for: language
            ))
        }
        if path.contains("/Developer/Xcode/iOS DeviceSupport/") || path.contains("/Developer/Xcode/watchOS DeviceSupport/") {
            return (.safe, L(
                "This is symbol data for a specific OS version. Xcode re-downloads it automatically the next time you debug on a device running that version.",
                "특정 OS 버전을 위한 심볼 데이터입니다. 해당 버전의 기기로 디버깅할 때 Xcode가 자동으로 다시 내려받습니다.",
                for: language
            ))
        }
        if path.contains("/.npm/") || path.contains("/.cache/") {
            // Unlike DerivedData or Device Support, this bucket can hold
            // anything from a small npm package cache to tens of GB of
            // downloaded ML models — regeneration cost varies too widely to
            // call it uniformly SAFE, so the user reviews what's actually
            // inside before removing it.
            return (.review, L(
                "This is a package manager or developer tool cache. It's regenerated automatically when needed, but some tools may need to re-download a large amount of data — review what's inside before removing.",
                "패키지 매니저 또는 개발 도구의 캐시입니다. 필요할 때 자동으로 다시 생성되지만, 일부 도구는 많은 양의 데이터를 다시 내려받아야 할 수 있으니 안에 무엇이 있는지 확인 후 삭제하세요.",
                for: language
            ))
        }
        return (.review, L(
            "This is developer tool data. Review it yourself before removing, in case a tool still needs it.",
            "개발 도구가 사용하는 데이터입니다. 아직 필요할 수도 있으니 삭제 전에 직접 확인하세요.",
            for: language
        ))
    }

    private static func protectedReason(for url: URL, language: AppLanguage) -> String {
        if ProtectedPathRegistry.isUserPersonalContent(url) {
            return L(
                "This is content you created. MyMacCleaner never touches personal documents, photos, or media.",
                "직접 만든 콘텐츠입니다. MyMacCleaner는 개인 문서, 사진, 미디어 파일에는 절대 손대지 않습니다.",
                for: language
            )
        }
        if ProtectedPathRegistry.isKeychainOrCertificate(url) {
            return L(
                "This holds security credentials (keychain or certificate data) and is never modified.",
                "보안 자격 증명(키체인 또는 인증서 데이터)이 들어 있어 절대 변경하지 않습니다.",
                for: language
            )
        }
        if ProtectedPathRegistry.isRunningApplication(url) {
            return L(
                "This application is currently running.",
                "현재 실행 중인 애플리케이션입니다.",
                for: language
            )
        }
        return L(
            "This is a protected macOS system location required for your Mac to run correctly.",
            "Mac이 정상적으로 동작하는 데 필요한 보호된 macOS 시스템 위치입니다.",
            for: language
        )
    }
}
