import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// An error indicating a type mismatch when decoding a pending request response.
struct TypeMismatchError: Swift.Error {}

/// A pending request with a continuation for the result.
struct PendingRequest<T> {
    let continuation: CheckedContinuation<T, Swift.Error>
}

/// A type-erased pending request.
struct AnyPendingRequest: Sendable {
    // Single client sends start queued. Existing server/batch callers retain
    // their original issued-request behavior.
    var isIssued: Bool
    let method: String?
    private let _resume: @Sendable (Result<Any, Swift.Error>) -> Void

    init<T: Sendable & Decodable>(_ request: PendingRequest<T>) {
        self.init(T.self) { request.continuation.resume(with: $0) }
    }

    init<T: Sendable & Decodable>(
        _ type: T.Type, method: String? = nil, isIssued: Bool = true,
        resume: @escaping @Sendable (Result<T, Swift.Error>) -> Void
    ) {
        self.method = method
        self.isIssued = isIssued
        _resume = { result in
            switch result {
            case .success(let value):
                if let typedValue = value as? T {
                    resume(.success(typedValue))
                } else if let value = value as? Value,
                    let data = try? JSONEncoder().encode(value),
                    let decoded = try? JSONDecoder().decode(T.self, from: data)
                {
                    resume(.success(decoded))
                } else {
                    resume(.failure(TypeMismatchError()))
                }
            case .failure(let error):
                resume(.failure(error))
            }
        }
    }

    func resume(returning value: Any) {
        _resume(.success(value))
    }

    func resume(throwing error: Swift.Error) {
        _resume(.failure(error))
    }
}
