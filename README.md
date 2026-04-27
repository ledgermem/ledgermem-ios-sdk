# LedgerMem iOS SDK

A platform-aware Swift SDK for [LedgerMem](https://proofly.dev). Built for
iOS apps that want async/await, Combine bindings, an offline cache, and
`BackgroundTasks` integration out of the box.

> Different from [`ledgermem-swift`](https://github.com/ledgermem/ledgermem-swift),
> which is the cross-platform pure-Swift SDK. This package targets iOS-first
> features (sqlite cache, BackgroundTasks, Combine).

## Install

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/ledgermem/ledgermem-ios-sdk.git", from: "0.1.0"),
```

Or in Xcode: File → Add Packages… and paste the URL.

Minimum: **iOS 16**, **macOS 13**, **Swift 5.9**.

## Basic usage

```swift
import LedgerMemiOS

let client = try LedgerMemClient(config: .init(
    apiKey: ProcessInfo.processInfo.environment["LEDGERMEM_API_KEY"]!,
    workspaceId: "ws_42"
))

let hits = try await client.search(SearchRequest(query: "design review"))
let memory = try await client.create(CreateMemoryInput(text: "Shipped v0.1"))
```

## Combine

```swift
import Combine
import LedgerMemiOS

let bag = Set<AnyCancellable>()

client.searchPublisher(SearchRequest(query: "weekly"))
    .receive(on: DispatchQueue.main)
    .sink(
        receiveCompletion: { print($0) },
        receiveValue: { hits in print(hits) }
    )
    .store(in: &bag)
```

## Offline cache

`MemoryCache` is a dependency-free SQLite wrapper. Useful for warm-start UI
and offline reads.

```swift
let cache = try MemoryCache(path: NSTemporaryDirectory() + "ledgermem.db")
let recent = try await client.list(limit: 50).memories
try cache.upsertAll(recent)
let cached = try cache.recent(limit: 20)
```

## Background refresh

Register at launch and submit a request when the app backgrounds:

```swift
// AppDelegate.application(_:didFinishLaunchingWithOptions:)
BackgroundSync.register(client: client, cache: cache)

// SceneDelegate.sceneDidEnterBackground(_:)
try? BackgroundSync.schedule()
```

Add `dev.proofly.ledgermem.sync` to the
`BGTaskSchedulerPermittedIdentifiers` array in your Info.plist.

## Errors

All async APIs throw `LedgerMemError`:

| Case                          | Meaning                                  |
| ----------------------------- | ---------------------------------------- |
| `.invalidConfiguration(msg)`  | API key or workspace id missing          |
| `.http(status, message, code)`| Non-2xx response from the API            |
| `.decoding(message)`          | JSON failed to decode into the model     |
| `.transport(message)`         | URLSession/network failure               |

## Testing

```bash
swift test
```

Tests use `URLProtocol` to mock HTTP — no network access required.

## License

MIT. See `LICENSE`.
