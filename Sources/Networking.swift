import Foundation

final class JellyfinNetworking: Sendable {
    static let shared = JellyfinNetworking()

    let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration)
    }
}
