import Foundation

@main
private enum CoreTestRunner {
    static func main() {
        var results = TestResults()

        check(PlaybackTime.ticks(from: .nan) == 0, "NaN is rejected", results: &results)
        check(PlaybackTime.ticks(from: .infinity) == 0, "infinity is rejected", results: &results)
        check(PlaybackTime.ticks(from: -.infinity) == 0, "negative infinity is rejected", results: &results)
        check(PlaybackTime.ticks(from: -1) == 0, "negative time is rejected", results: &results)
        check(PlaybackTime.ticks(from: 1) == 10_000_000, "seconds convert to ticks", results: &results)
        check(PlaybackTime.ticks(from: 1.5) == 15_000_000, "fractional seconds convert to ticks", results: &results)

        let first = track(id: "local-a", itemID: "remote")
        let sameRemote = track(id: "local-b", itemID: "remote")
        check(first.matches(sameRemote), "track identity prefers Jellyfin item ID", results: &results)

        let localFirst = track(id: "local-a", itemID: nil)
        let localSecond = track(id: "local-b", itemID: nil)
        check(!localFirst.matches(localSecond), "track identity requires Jellyfin IDs", results: &results)

        let differentRemote = track(id: "local-c", itemID: "other-remote")
        check(!first.matches(differentRemote), "different Jellyfin IDs are different tracks", results: &results)

        let queue = [
            track(id: "queue-a", itemID: "remote-a"),
            track(id: "queue-b", itemID: "remote-b")
        ]
        check(PlaybackQueueState.currentIndex(in: queue, for: queue[1]) == 1, "queue finds current track by ID", results: &results)
        check(PlaybackQueueState.currentIndex(in: queue, for: track(id: "outside", itemID: "outside-remote")) == nil, "queue ignores external current track", results: &results)
        check(PlaybackQueueState.nextIndex(in: queue, from: 0, wrapping: false) == 1, "queue advances to next track", results: &results)
        check(PlaybackQueueState.nextIndex(in: queue, from: 1, wrapping: false) == nil, "queue stops at end without repeat", results: &results)
        check(PlaybackQueueState.previousIndex(in: queue, from: 0, wrapping: true) == 1, "queue wraps to previous track", results: &results)

        let artworkTrack = track(id: "track-local", itemID: "track-remote")
        check(ArtworkReference.itemID(for: artworkTrack) == "track-remote", "artwork uses track Jellyfin ID", results: &results)
        var albumArtworkTrack = artworkTrack
        albumArtworkTrack.albumID = "album-remote"
        check(ArtworkReference.itemID(for: albumArtworkTrack) == "album-remote", "artwork prefers album Jellyfin ID", results: &results)
        check(ArtworkReference.cacheKey(itemID: "album-remote", maxWidth: 2) == "album-remote-w64", "artwork cache width has a lower bound", results: &results)

        let session = JellyfinSession(serverURL: URL(string: "https://jellyfin.local")!, userID: "user-id", userName: "user", accessToken: "token", deviceID: "device")
        let encodedSession = try? SessionCodec.encode(session)
        check(encodedSession.flatMap(SessionCodec.decode)?.accessToken == "token", "session codec round-trips auth data", results: &results)
        check(SessionCodec.decode("not-json") == nil, "session codec rejects invalid data", results: &results)

        check(ServerVersion("12.0.0")?.major == 12, "server version parses major", results: &results)
        check(ServerVersion("10.9")?.patch == 0, "server version fills missing components", results: &results)
        check(ServerVersion("10.10.0-rc1")?.minor == 10, "server version ignores prerelease suffix", results: &results)
        check(ServerVersion("")  == nil, "server version rejects empty string", results: &results)
        check(ServerVersion("dev") == nil, "server version rejects non-numeric string", results: &results)
        if let older = ServerVersion("10.11.11"), let newer = ServerVersion("12.0.0") {
            check(older < newer, "server versions compare numerically", results: &results)
            check(ServerVersion("10.9.0")! < older, "server versions compare by minor", results: &results)
        } else {
            check(false, "server versions parse for comparison", results: &results)
        }

        var sessionWithServer = session
        sessionWithServer.server = JellyfinServerInfo(
            name: "media",
            productName: "Jellyfin Server",
            version: ServerVersion("12.0.0"),
            rawVersion: "12.0.0"
        )
        let restoredServer = (try? SessionCodec.encode(sessionWithServer)).flatMap(SessionCodec.decode)?.server
        check(restoredServer?.version == ServerVersion("12.0.0"), "session codec round-trips server version", results: &results)
        check(restoredServer?.displayText == "media — Jellyfin Server 12.0.0", "server info renders display text", results: &results)

        check(sessionWithServer.server?.isVerifiedVersion == true, "12.0.0 is a verified server version", results: &results)
        var oldServer = sessionWithServer.server
        oldServer?.version = ServerVersion("10.9.0")
        check(oldServer?.isVerifiedVersion == false, "10.9.0 is below the verified range", results: &results)
        check(JellyfinServerInfo(name: nil, productName: nil, version: nil, rawVersion: "dev").isVerifiedVersion == nil, "unparsed version has no verdict", results: &results)

        let legacySessionJSON = #"{"serverURL":"https://jellyfin.local","userID":"user-id","userName":"user","accessToken":"token","deviceID":"device"}"#
        check(SessionCodec.decode(legacySessionJSON)?.server == nil, "session codec reads sessions saved without server info", results: &results)

        let artists = [
            Artist(id: "artist-a", itemID: "artist-remote-a", name: "A", genre: "Music", songCount: 0),
            Artist(id: "artist-b", itemID: "artist-remote-b", name: "B", genre: "Music", songCount: 0)
        ]
        let projectedArtists = LibraryProjection.artists(artists, applying: ["artist-remote-b": 12])
        check(projectedArtists[1].songCount == 12 && projectedArtists[0].songCount == 0, "library projection applies counts by ID", results: &results)
        check(LibraryProjection.artistIndexByID(projectedArtists)["artist-remote-b"] == 1, "library projection indexes artists by ID", results: &results)

        let legacyArtistJSON = Data(#"{"id":"artist","itemID":"remote","name":"Artist","genre":"Music","trackCount":4}"#.utf8)
        let legacyArtist = try? JSONDecoder().decode(Artist.self, from: legacyArtistJSON)
        check(legacyArtist?.songCount == 4, "legacy artist cache preserves song count", results: &results)

        let album = Album(
            id: "album-local",
            itemID: "album-remote",
            title: "Album",
            artist: "Artist",
            year: 2023,
            releaseDate: "2023-12-24T00:00:00Z",
            trackCount: 10,
            durationText: "40m"
        )
        check(album.itemID == "album-remote", "album keeps Jellyfin item ID", results: &results)
        let albumRoute = LibraryRoute.album(album)
        check(albumRoute.itemID == "album-remote", "album navigation keeps Jellyfin item ID", results: &results)

        let artist = Artist(id: "artist-local", itemID: "artist-remote", name: "Artist", genre: "Music", songCount: 10)
        check(LibraryRoute.artist(artist).itemID == "artist-remote", "artist navigation keeps Jellyfin item ID", results: &results)

        let playlist = Playlist(id: "playlist-local", itemID: "playlist-remote", name: "Playlist", trackCount: 10, durationText: "40m")
        check(LibraryRoute.playlist(playlist).itemID == "playlist-remote", "playlist navigation keeps Jellyfin item ID", results: &results)
        check(album.releaseText(format: .year) == "2023", "year date format", results: &results)
        check(album.releaseText(format: .monthAndYear) != "2023", "month and year date format", results: &results)
        check(album.releaseText(format: .fullDate) != "2023", "full date format", results: &results)
        check(DateDisplayFormat.allCases.count == 3, "three date formats are available", results: &results)

        let itemWithUserData = Data(#"{"Id":"track","Name":"Track","UserData":{"IsFavorite":true}}"#.utf8)
        let decodedUserData = try? JSONDecoder().decode(JellyfinItemDTO.self, from: itemWithUserData)
        check(decodedUserData?.isFavorite == true, "item DTO reads favorite flag from UserData", results: &results)

        let itemWithoutFavorite = Data(#"{"Id":"track","Name":"Track","UserData":{"PlayCount":2}}"#.utf8)
        let decodedNoFavorite = try? JSONDecoder().decode(JellyfinItemDTO.self, from: itemWithoutFavorite)
        check(decodedNoFavorite?.isFavorite == nil, "item DTO keeps favorite flag empty without UserData value", results: &results)

        let itemWithRootFavorite = Data(#"{"Id":"track","Name":"Track","IsFavorite":true}"#.utf8)
        let decodedRootFavorite = try? JSONDecoder().decode(JellyfinItemDTO.self, from: itemWithRootFavorite)
        check(decodedRootFavorite?.isFavorite == true, "item DTO falls back to root favorite flag", results: &results)

        let itemFavoriteConflict = Data(#"{"Id":"track","Name":"Track","IsFavorite":true,"UserData":{"IsFavorite":false}}"#.utf8)
        let decodedConflict = try? JSONDecoder().decode(JellyfinItemDTO.self, from: itemFavoriteConflict)
        check(decodedConflict?.isFavorite == false, "item DTO prefers UserData over root favorite flag", results: &results)

        guard results.failures == 0 else {
            print("Core tests failed: \(results.failures)")
            exit(EXIT_FAILURE)
        }
        print("Core tests passed: \(results.total)")
    }

    private struct TestResults {
        var total = 0
        var failures = 0
    }

    private static func check(_ condition: Bool, _ name: String, results: inout TestResults) {
        results.total += 1
        if !condition {
            results.failures += 1
            print("FAIL: \(name)")
        }
    }

    private static func track(id: String, itemID: String?) -> Track {
        Track(
            id: id,
            itemID: itemID,
            title: "Track",
            artist: "Artist",
            album: "Album",
            duration: 120,
            isFavorite: false
        )
    }
}
