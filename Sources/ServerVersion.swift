import Foundation

/// Версия сервера Jellyfin в сравнимом виде.
///
/// Кодируется исходной строкой, поэтому сохранённая сессия остаётся читаемой
/// и при изменении разбора.
struct ServerVersion: Sendable, Comparable, Codable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let raw: String

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Отбрасываем предрелизные и сборочные суффиксы: 10.9.0-rc1, 12.0.0+build.
        let core = trimmed.prefix { $0.isNumber || $0 == "." }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard let first = numbers.first, let major = first else { return nil }

        self.major = major
        minor = numbers.count > 1 ? (numbers[1] ?? 0) : 0
        patch = numbers.count > 2 ? (numbers[2] ?? 0) : 0
        self.raw = trimmed
    }

    /// Ниже этой версии совместимость не проверялась: локальных схем API для сверки нет.
    static let minimumVerified = ServerVersion("10.11")!

    var description: String { raw }

    static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    static func == (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) == (rhs.major, rhs.minor, rhs.patch)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = ServerVersion(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported version: \(raw)")
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

/// Сведения о сервере из `/System/Info/Public`.
struct JellyfinServerInfo: Sendable, Codable, Equatable {
    var name: String?
    var productName: String?
    /// Разобранная версия; `nil`, если сервер вернул нераспознанную строку.
    var version: ServerVersion?
    /// Исходная строка версии — её и показываем пользователю.
    var rawVersion: String?

    /// `nil` — версию распознать не удалось, о совместимости судить нечего.
    var isVerifiedVersion: Bool? {
        version.map { $0 >= ServerVersion.minimumVerified }
    }

    var displayText: String {
        let product = productName ?? "Jellyfin"
        let version = rawVersion ?? "unknown version"
        guard let name, !name.isEmpty else { return "\(product) \(version)" }
        return "\(name) — \(product) \(version)"
    }
}
