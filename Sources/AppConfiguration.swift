import Foundation

enum AppConfiguration {
    static let name = "Jellia"
    static let defaultArtworkCacheSizeMB = 512

    enum DefaultsKey {
        static let serverURL = "serverURL"
        static let cacheSizeMB = "cacheSizeMB"
        static let dateDisplayFormat = "dateDisplayFormat"
        static let deviceID = "jellia.deviceID"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
