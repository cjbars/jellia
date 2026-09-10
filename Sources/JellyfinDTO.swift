import Foundation

struct JellyfinAuthResponse: Decodable {
    struct User: Decodable {
        let id: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
        }
    }

    struct SessionInfo: Decodable {
        let userId: String?

        enum CodingKeys: String, CodingKey {
            case userId = "UserId"
        }
    }

    let accessToken: String?
    let user: User?
    let sessionInfo: SessionInfo?

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
        case sessionInfo = "SessionInfo"
    }
}

struct JellyfinPublicSystemInfoDTO: Decodable {
    let serverName: String?
    let version: String?
    let productName: String?

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
    }
}

struct JellyfinItemsResponse: Decodable {
    let items: [JellyfinItemDTO]
    let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct JellyfinItemLinkDTO: Decodable {
    let name: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

struct JellyfinUserItemDataDTO: Decodable {
    let isFavorite: Bool?

    enum CodingKeys: String, CodingKey {
        case isFavorite = "IsFavorite"
    }
}

struct JellyfinItemDTO: Decodable {
    let id: String?
    let parentID: String?
    let name: String?
    let type: String?
    let album: String?
    let albumID: String?
    let albumArtist: String?
    let artists: [String]?
    let albumArtists: [JellyfinItemLinkDTO]?
    let artistItems: [JellyfinItemLinkDTO]?
    let productionYear: Int?
    let premiereDate: String?
    let dateCreated: String?
    let overview: String?
    let genres: [String]?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let runTimeTicks: Int64?
    let userData: JellyfinUserItemDataDTO?
    let rootIsFavorite: Bool?
    let childCount: Int?
    let songCount: Int?
    let albumCount: Int?
    let mediaSources: [JellyfinMediaSourceDTO]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case parentID = "ParentId"
        case name = "Name"
        case type = "Type"
        case album = "Album"
        case albumID = "AlbumId"
        case albumArtist = "AlbumArtist"
        case artists = "Artists"
        case albumArtists = "AlbumArtists"
        case artistItems = "ArtistItems"
        case productionYear = "ProductionYear"
        case premiereDate = "PremiereDate"
        case dateCreated = "DateCreated"
        case overview = "Overview"
        case genres = "Genres"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case runTimeTicks = "RunTimeTicks"
        case userData = "UserData"
        case rootIsFavorite = "IsFavorite"
        case childCount = "ChildCount"
        case songCount = "SongCount"
        case albumCount = "AlbumCount"
        case mediaSources = "MediaSources"
    }

    /// Признак избранного приходит в `UserData` (`UserItemDataDto`); корневой `IsFavorite` — запасной вариант.
    var isFavorite: Bool? { userData?.isFavorite ?? rootIsFavorite }
}

struct JellyfinMediaSourceDTO: Decodable {
    let id: String?
    let container: String?
    let transcodingUrl: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let requiredHttpHeaders: [String: String?]?
    let mediaSourceId: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case container = "Container"
        case transcodingUrl = "TranscodingUrl"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case requiredHttpHeaders = "RequiredHttpHeaders"
        case mediaSourceId = "MediaSourceId"
    }
}

struct JellyfinPlaybackInfoResponse: Decodable {
    let mediaSources: [JellyfinMediaSourceDTO]?
    let playSessionID: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionID = "PlaySessionId"
    }
}

struct JellyfinPlaybackInfoRequest: Encodable {
    let userID: String
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "UserId"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
    }
}

struct JellyfinPlaybackReportStart: Encodable {
    let itemID: String
    let playSessionID: String?
    let mediaSourceID: String?
    let positionTicks: Int64
    let isPaused: Bool
    let playMethod: String

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case playSessionID = "PlaySessionId"
        case mediaSourceID = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case playMethod = "PlayMethod"
    }
}

struct JellyfinPlaybackReportProgress: Encodable {
    let itemID: String
    let playSessionID: String?
    let mediaSourceID: String?
    let positionTicks: Int64
    let isPaused: Bool
    let canSeek: Bool

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case playSessionID = "PlaySessionId"
        case mediaSourceID = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case canSeek = "CanSeek"
    }
}

struct JellyfinPlaybackReportStop: Encodable {
    let itemID: String
    let playSessionID: String?
    let mediaSourceID: String?
    let positionTicks: Int64
    let failed: Bool

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case playSessionID = "PlaySessionId"
        case mediaSourceID = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case failed = "Failed"
    }
}

struct EmptyBody: Encodable {}
