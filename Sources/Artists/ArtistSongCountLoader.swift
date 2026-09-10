import Foundation

private actor AsyncRequestLimiter {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        availablePermits = max(limit, 1)
    }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

actor ArtistSongCountLoader {
    private struct InFlight {
        let token: UUID
        let task: Task<Int, Error>
    }

    private let limiter: AsyncRequestLimiter
    private var cache: [String: Int] = [:]
    private var inFlight: [String: InFlight] = [:]

    init(maxConcurrentRequests: Int) {
        limiter = AsyncRequestLimiter(limit: maxConcurrentRequests)
    }

    func count(
        artistID: String,
        session: JellyfinSession,
        client: any JellyfinAPI
    ) async throws -> Int {
        if let cached = cache[artistID] {
            return cached
        }

        let request: InFlight
        if let existing = inFlight[artistID] {
            request = existing
        } else {
            let token = UUID()
            let task = Task<Int, Error> {
                await self.limiter.acquire()
                do {
                    try Task.checkCancellation()
                    let count = try await client.loadArtistSongCount(artistID: artistID, session: session)
                    await self.limiter.release()
                    return count
                } catch {
                    await self.limiter.release()
                    throw error
                }
            }
            request = InFlight(token: token, task: task)
            inFlight[artistID] = request
        }

        do {
            let count = try await request.task.value
            if inFlight[artistID]?.token == request.token {
                inFlight[artistID] = nil
                cache[artistID] = count
            }
            return count
        } catch {
            if inFlight[artistID]?.token == request.token {
                inFlight[artistID] = nil
            }
            throw error
        }
    }

    func cancelPending() {
        inFlight.values.forEach { $0.task.cancel() }
        inFlight.removeAll()
    }

    func reset() {
        cancelPending()
        cache.removeAll()
    }
}
