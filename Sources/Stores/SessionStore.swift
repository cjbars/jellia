import Foundation

enum SessionCodec {
    static func encode(_ session: JellyfinSession) throws -> String {
        let data = try JSONEncoder().encode(session)
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ value: String) -> JellyfinSession? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JellyfinSession.self, from: data)
    }
}

final class SessionStore {
    private static let key = "jellia.auth.session"
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func save(_ session: JellyfinSession) throws {
        try keychain.saveString(SessionCodec.encode(session), for: Self.key)
    }

    func load() throws -> JellyfinSession? {
        guard let value = try keychain.readString(for: Self.key) else { return nil }
        return SessionCodec.decode(value)
    }

    func clear() throws {
        try keychain.deleteValue(for: Self.key)
    }
}
