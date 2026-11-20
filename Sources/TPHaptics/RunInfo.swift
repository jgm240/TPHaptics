import Foundation
import Security

/// Facts about the running copy of the app. macOS ties the Accessibility permission to a signed
/// app bundle, so a bare executable (for example from `swift run`) can never hold it.
enum RunInfo {
    static var path: String { Bundle.main.bundlePath }

    /// false when running the loose executable instead of TPHaptics.app.
    static var isBundled: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    static var signing: String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return "unknown" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return "unknown" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "unsigned" }
        let flags = dict[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        if flags & 0x2 != 0 { return "ad-hoc signed" }          // kSecCodeSignatureAdhoc
        return dict[kSecCodeInfoIdentifier as String] != nil ? "signed" : "unsigned"
    }

    /// One line for the log and the Notifications screen.
    static var summary: String {
        "\(isBundled ? "app" : "bare executable") · \(signing) · pid \(ProcessInfo.processInfo.processIdentifier) · \(path)"
    }
}
