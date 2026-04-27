#if canImport(Combine)
import Combine
import Foundation

/// Optional Combine bindings. Subscribers run the request inside a `Task`
/// and bridge the result into a `Future`-style publisher.
@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public extension LedgerMemClient {
    nonisolated func searchPublisher(_ request: SearchRequest) -> AnyPublisher<[SearchHit], LedgerMemError> {
        Future { promise in
            Task {
                do {
                    let hits = try await self.search(request)
                    promise(.success(hits))
                } catch let err as LedgerMemError {
                    promise(.failure(err))
                } catch {
                    promise(.failure(.transport(error.localizedDescription)))
                }
            }
        }.eraseToAnyPublisher()
    }

    nonisolated func createPublisher(_ input: CreateMemoryInput) -> AnyPublisher<Memory, LedgerMemError> {
        Future { promise in
            Task {
                do {
                    let memory = try await self.create(input)
                    promise(.success(memory))
                } catch let err as LedgerMemError {
                    promise(.failure(err))
                } catch {
                    promise(.failure(.transport(error.localizedDescription)))
                }
            }
        }.eraseToAnyPublisher()
    }

    nonisolated func listPublisher(cursor: String? = nil, limit: Int? = nil) -> AnyPublisher<ListResult, LedgerMemError> {
        Future { promise in
            Task {
                do {
                    let result = try await self.list(cursor: cursor, limit: limit)
                    promise(.success(result))
                } catch let err as LedgerMemError {
                    promise(.failure(err))
                } catch {
                    promise(.failure(.transport(error.localizedDescription)))
                }
            }
        }.eraseToAnyPublisher()
    }
}
#endif
