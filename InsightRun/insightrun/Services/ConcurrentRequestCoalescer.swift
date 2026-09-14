import Foundation

@MainActor
final class ConcurrentRequestCoalescer<Key: Hashable, Value> {
    private var waiters: [Key: [CheckedContinuation<Value, Error>]] = [:]

    func value(for key: Key, operation: () async throws -> Value) async throws -> Value {
        if waiters[key] != nil {
            return try await withCheckedThrowingContinuation { continuation in
                waiters[key, default: []].append(continuation)
            }
        }

        waiters[key] = []
        let result: Result<Value, Error>
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }

        let pending = waiters.removeValue(forKey: key) ?? []
        for continuation in pending {
            continuation.resume(with: result)
        }
        return try result.get()
    }
}
