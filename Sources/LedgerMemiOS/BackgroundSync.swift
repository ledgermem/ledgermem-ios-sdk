#if canImport(BackgroundTasks)
import BackgroundTasks
import Foundation

/// Helpers for registering a background refresh task that pulls the most
/// recent memories so the cache stays warm.
@available(iOS 16, *)
public enum BackgroundSync {
    public static let defaultIdentifier = "dev.proofly.ledgermem.sync"

    /// Register the handler with `BGTaskScheduler` once at app launch
    /// (typically from `application(_:didFinishLaunchingWithOptions:)`).
    @MainActor
    public static func register(
        identifier: String = defaultIdentifier,
        client: LedgerMemClient,
        cache: MemoryCache,
        pageLimit: Int = 50
    ) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: refresh, client: client, cache: cache, pageLimit: pageLimit)
        }
    }

    /// Submit a refresh request. Call after the app moves to the background.
    public static func schedule(
        identifier: String = defaultIdentifier,
        earliest: Date = Date().addingTimeInterval(15 * 60)
    ) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliest
        try BGTaskScheduler.shared.submit(request)
    }

    private static func handle(
        task: BGAppRefreshTask,
        client: LedgerMemClient,
        cache: MemoryCache,
        pageLimit: Int
    ) {
        let job = Task {
            do {
                let result = try await client.list(limit: pageLimit)
                try cache.upsertAll(result.memories)
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { job.cancel() }
    }
}
#endif
