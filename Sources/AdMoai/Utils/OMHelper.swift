import Foundation

public extension Creative {
    func getVerificationResources() -> [VerificationScriptResource]? {
        verificationScriptResources
    }

    func hasOMVerification() -> Bool {
        guard let resources = verificationScriptResources else {
            return false
        }
        return !resources.isEmpty
    }
}
