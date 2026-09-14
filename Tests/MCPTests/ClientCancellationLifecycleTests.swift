import Foundation
import Logging
import Testing

@testable import MCP

@Suite("Client cancellation lifecycle", .timeLimit(.minutes(1)))
struct ClientCancellationLifecycleTests {
    @Test func cancelBeforeSendingTaskRuns() async throws {
        let transport = CancellationTransport()
        let client = Client(name: "test", version: "1")
        try await client.connect(transport: transport)
        let request = ReadResource.request(.init(uri: "test://late"))
        let context = try await client.sendAndImmediatelyCancel(request)
        // A response after cancellation must not resurrect the local request.
        try await transport.reply(to: request)
        await #expect(throws: CancellationError.self) { try await context.value }
        try await client.ping()
        #expect(await transport.resourceCount == 0)
        await client.disconnect()
    }

    @Test func convenienceCancellationAndIndependentRequest() async throws {
        let transport = CancellationTransport()
        let client = Client(name: "test", version: "1")
        try await client.connect(transport: transport)
        let request = Task { try await client.readResource(uri: "test://slow") }
        var arrivals = transport.resources.makeAsyncIterator()
        let pending = try #require(await arrivals.next())
        let independent = Task { try await client.readResource(uri: "test://other") }
        let other = try #require(await arrivals.next())
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        try await transport.reply(to: pending)
        try await transport.reply(to: other)
        #expect(try await independent.value.isEmpty)
        try await client.ping()
        await client.disconnect()
    }

    @Test func alreadyCancelledConvenienceCallDoesNotSend() async throws {
        let transport = CancellationTransport()
        let client = Client(name: "test", version: "1")
        try await client.connect(transport: transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.readResource(uri: "test://cancelled")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.resourceCount == 0)
        try await client.ping()
        await client.disconnect()
    }

    @Test func failedSendCompletesRequestAndConnectionRemainsUsable() async throws {
        let transport = CancellationTransport()
        let client = Client(name: "test", version: "1")
        try await client.connect(transport: transport)
        await transport.failResourceSend()
        await #expect(throws: MCPError.self) {
            try await client.readResource(uri: "test://failure")
        }
        try await client.ping()
        await client.disconnect()
    }
}

extension Client {
    // Execute send and the synchronous prefix of cancelRequest in one actor
    // turn, before the child send task can register/send on the old SDK.
    fileprivate func sendAndImmediatelyCancel(_ request: Request<ReadResource>) async throws
        -> RequestContext<ReadResource.Result>
    {
        let context = try send(request)
        try await cancelRequest(context.requestID)
        return context
    }
}

private actor CancellationTransport: Transport {
    let logger = Logger(label: "test.cancellation")
    private let inbound = AsyncThrowingStream<Data, Error>.makeStream()
    nonisolated let resources: AsyncStream<Request<ReadResource>>
    private let resourceContinuation: AsyncStream<Request<ReadResource>>.Continuation
    private(set) var resourceCount = 0
    private var failSend = false

    init() {
        let pair = AsyncStream<Request<ReadResource>>.makeStream()
        resources = pair.stream
        resourceContinuation = pair.continuation
    }
    func connect() async throws {}
    func disconnect() async {
        inbound.continuation.finish()
        resourceContinuation.finish()
    }
    func receive() -> AsyncThrowingStream<Data, Error> { inbound.stream }
    func failResourceSend() { failSend = true }
    func send(_ data: Data) async throws {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch object?["method"] as? String {
        case Initialize.name:
            let request = try JSONDecoder().decode(Request<Initialize>.self, from: data)
            inbound.continuation.yield(
                try JSONEncoder().encode(
                    Initialize.response(
                        id: request.id,
                        result: .init(
                            protocolVersion: Version.latest,
                            capabilities: .init(resources: .init()),
                            serverInfo: .init(name: "test", version: "1")))))
        case Ping.name:
            let request = try JSONDecoder().decode(Request<Ping>.self, from: data)
            inbound.continuation.yield(
                try JSONEncoder().encode(Ping.response(id: request.id, result: Empty())))
        case ReadResource.name:
            if failSend { throw MCPError.internalError("test send failure") }
            resourceCount += 1
            resourceContinuation.yield(
                try JSONDecoder().decode(Request<ReadResource>.self, from: data))
        default: break
        }
    }
    func reply(to request: Request<ReadResource>) throws {
        inbound.continuation.yield(
            try JSONEncoder().encode(
                ReadResource.response(
                    id: request.id,
                    result: .init(contents: []))))
    }
}
