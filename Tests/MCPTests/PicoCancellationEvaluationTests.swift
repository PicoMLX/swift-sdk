import Foundation
import Logging
import Testing

@testable import MCP

@Suite("Client cancellation lifecycle", .timeLimit(.minutes(1)))
struct ClientCancellationLifecycleTests {
    @Test func cancellationAfterCompletionDoesNotRetainMarkers() async throws {
        let transport = CancellationTransport()
        let client = Client(name: "test", version: "1")
        try await client.connect(transport: transport)
        for _ in 0..<32 {
            let context = try await client.send(Ping.request())
            _ = try await context.value
            try await client.cancelRequest(context.requestID)
        }
        let retainedMarkers = await client.markerCountForEvaluation()
        #expect(retainedMarkers == 0)
        try await client.ping()
        await client.disconnect()
        #expect(await client.markerCountForEvaluation() == 0)
    }

    @Test func cancellationDuringSendReleasesCallerAndNotifiesPromptly() async throws {
        let transport = CancellationTransport(delayResourceSend: true)
        let client = Client(name: "test", version: "1")
        try await client.connect(transport: transport)
        let request = Task { try await client.readResource(uri: "test://suspended-send") }
        var sends = transport.suspendedSends.makeAsyncIterator()
        _ = try #require(await sends.next())
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        var cancellations = transport.cancellations.makeAsyncIterator()
        let cancelledID = try #require(await cancellations.next())
        try await client.ping()
        await transport.finishResourceSend()
        var arrivals = transport.resources.makeAsyncIterator()
        let sent = try #require(await arrivals.next())
        #expect(cancelledID == sent.id)
        // Transport.send can suspend before dispatch OR while awaiting a
        // response. Without a dispatch seam the advisory notice can overtake
        // the request; waiting for send would deadlock response-waiting HTTP.
        let wire = await transport.resourceWireEvents
        #expect(wire == ["cancel", "request"])
        try await transport.reply(to: sent)
        try await client.ping()
        await client.disconnect()
    }

    @Test func oldHandshakeCannotReplaceNewConnection() async throws {
        let original = CancellationTransport(delayConnect: true)
        let client = Client(name: "test", version: "1")
        let oldConnect = Task { try await client.connect(transport: original) }
        var starts = original.connectStarts.makeAsyncIterator()
        _ = try #require(await starts.next())
        await client.disconnect()
        let replacement = CancellationTransport()
        try await client.connect(transport: replacement)
        await original.finishConnect()
        await #expect(throws: MCPError.self) { try await oldConnect.value }
        #expect(await replacement.disconnectCount == 0)
        try await client.ping()
        await client.disconnect()
    }

    @Test func disconnectedFinalHandshakeDoesNotReturnSuccess() async throws {
        let transport = CancellationTransport(delayFinalization: true)
        let client = Client(name: "test", version: "1")
        let connecting = Task { try await client.connect(transport: transport) }
        var finalizations = transport.finalizations.makeAsyncIterator()
        _ = try #require(await finalizations.next())
        await client.disconnect()
        await #expect(throws: MCPError.self) { try await connecting.value }
        #expect(await transport.disconnectCount == 1)
    }

    @Test func explicitBatchCancellationStillCompletesLocally() async throws {
        let transport = CancellationTransport()
        let client = Client(name: "test", version: "1")
        try await client.connect(transport: transport)
        try await client.withBatch { batch in
            let request = ReadResource.request(.init(uri: "test://batch"))
            let result = try await batch.addRequest(request)
            try await client.cancelRequest(request.id)
            await #expect(throws: CancellationError.self) { try await result.value }
        }
        try await client.ping()
        let markers = await client.markerCountForEvaluation()
        #expect(markers == 0)
        await client.disconnect()
    }

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
        #expect(await transport.cancellationCount == 0)
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
        var cancellations = transport.cancellations.makeAsyncIterator()
        #expect(await cancellations.next() == pending.id)
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

    @Test func cancellingInitializationDoesNotSendCancellationNotification() async throws {
        let transport = CancellationTransport(delayInitialization: true)
        let client = Client(name: "test", version: "1")
        let connecting = Task { try await client.connect(transport: transport) }
        var arrivals = transport.initializations.makeAsyncIterator()
        _ = try #require(await arrivals.next())
        connecting.cancel()
        await #expect(throws: CancellationError.self) { try await connecting.value }
        #expect(await transport.cancellationCount == 0)
        #expect(await transport.disconnectCount == 1)
        await #expect(throws: MCPError.self) { try await client.ping() }
        let replacement = CancellationTransport()
        try await client.connect(transport: replacement)
        try await client.ping()
        await client.disconnect()
        #expect(await replacement.disconnectCount == 1)
    }

    @Test func cancellationDuringFinalHandshakeNotificationDisconnects() async throws {
        let transport = CancellationTransport(delayFinalization: true)
        let client = Client(name: "test", version: "1")
        let connecting = Task { try await client.connect(transport: transport) }
        var finalizations = transport.finalizations.makeAsyncIterator()
        _ = try #require(await finalizations.next())
        connecting.cancel()
        await transport.finishFinalization()
        await #expect(throws: CancellationError.self) { try await connecting.value }
        #expect(await transport.disconnectCount == 1)
        await #expect(throws: MCPError.self) { try await client.ping() }
    }

    @Test func cancellationTakesPrecedenceOverRacingSendFailure() async throws {
        let transport = CancellationTransport()
        let client = Client(name: "test", version: "1")
        try await client.connect(transport: transport)
        let reference = CancellationReference()
        await transport.cancelWhenSendingResource { await reference.cancel() }
        let gate = AsyncStream<Void>.makeStream()
        let request = Task {
            var start = gate.stream.makeAsyncIterator()
            _ = await start.next()
            return try await client.readResource(uri: "test://cancel-and-fail")
        }
        await reference.set(request)
        gate.continuation.finish()
        await #expect(throws: CancellationError.self) { try await request.value }
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
    // Evaluation-only observation of existing private state. No production seam
    // or change is added to the candidate tag, and no concurrent actor access.
    fileprivate func markerCountForEvaluation() -> Int {
        let markers = Mirror(reflecting: self).children.first {
            $0.label == "cancelledBeforeRegistration"
        }?.value as? Set<ID>
        return markers?.count ?? -1
    }

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
    private(set) var disconnectCount = 0
    private(set) var resourceCount = 0
    private(set) var cancellationCount = 0
    nonisolated let cancellations: AsyncStream<ID>
    private let cancellationContinuation: AsyncStream<ID>.Continuation
    nonisolated let initializations: AsyncStream<ID>
    private let initializationContinuation: AsyncStream<ID>.Continuation
    private let delayInitialization: Bool
    private let delayFinalization: Bool
    nonisolated let finalizations: AsyncStream<Void>
    private let finalizationContinuation: AsyncStream<Void>.Continuation
    private var blockedFinalization: CheckedContinuation<Void, Never>?
    private let delayConnect: Bool
    nonisolated let connectStarts: AsyncStream<Void>
    private let connectStartContinuation: AsyncStream<Void>.Continuation
    private var blockedConnect: CheckedContinuation<Void, Never>?
    private let delayResourceSend: Bool
    nonisolated let suspendedSends: AsyncStream<Void>
    private let suspendedSendContinuation: AsyncStream<Void>.Continuation
    private var blockedResourceSend: CheckedContinuation<Void, Never>?
    private(set) var resourceWireEvents: [String] = []
    private var failSend = false
    private var cancelOnSend: (@Sendable () async -> Void)?

    init(delayInitialization: Bool = false, delayFinalization: Bool = false, delayResourceSend: Bool = false, delayConnect: Bool = false) {
        self.delayConnect = delayConnect
        let connectStart = AsyncStream<Void>.makeStream()
        connectStarts = connectStart.stream
        connectStartContinuation = connectStart.continuation
        self.delayResourceSend = delayResourceSend
        let suspendedSend = AsyncStream<Void>.makeStream()
        suspendedSends = suspendedSend.stream
        suspendedSendContinuation = suspendedSend.continuation
        self.delayInitialization = delayInitialization
        self.delayFinalization = delayFinalization
        let finalization = AsyncStream<Void>.makeStream()
        finalizations = finalization.stream
        finalizationContinuation = finalization.continuation
        let cancellation = AsyncStream<ID>.makeStream()
        cancellations = cancellation.stream
        cancellationContinuation = cancellation.continuation
        let initialization = AsyncStream<ID>.makeStream()
        initializations = initialization.stream
        initializationContinuation = initialization.continuation
        let pair = AsyncStream<Request<ReadResource>>.makeStream()
        resources = pair.stream
        resourceContinuation = pair.continuation
    }
    func connect() async throws {
        if delayConnect {
            await withCheckedContinuation {
                blockedConnect = $0
                connectStartContinuation.yield(())
            }
        }
    }
    func finishConnect() {
        blockedConnect?.resume()
        blockedConnect = nil
    }
    func disconnect() async {
        disconnectCount += 1
        inbound.continuation.finish()
        resourceContinuation.finish()
        initializationContinuation.finish()
        cancellationContinuation.finish()
        finalizationContinuation.finish()
        finishFinalization()
        finishResourceSend()
        suspendedSendContinuation.finish()
    }
    func finishResourceSend() {
        blockedResourceSend?.resume()
        blockedResourceSend = nil
    }
    func finishFinalization() {
        blockedFinalization?.resume()
        blockedFinalization = nil
    }
    func receive() -> AsyncThrowingStream<Data, Error> { inbound.stream }
    func cancelWhenSendingResource(_ action: @escaping @Sendable () async -> Void) { cancelOnSend = action }
    func failResourceSend() { failSend = true }
    func send(_ data: Data) async throws {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch object?["method"] as? String {
        case Initialize.name:
            let request = try JSONDecoder().decode(Request<Initialize>.self, from: data)
            initializationContinuation.yield(request.id)
            if delayInitialization { return }
            inbound.continuation.yield(
                try JSONEncoder().encode(
                    Initialize.response(
                        id: request.id,
                        result: .init(
                            protocolVersion: Version.latest,
                            capabilities: .init(resources: .init()),
                            serverInfo: .init(name: "test", version: "1")))))
        case InitializedNotification.name:
            if delayFinalization {
                await withCheckedContinuation {
                    blockedFinalization = $0
                    finalizationContinuation.yield(())
                }
            }
        case Ping.name:
            let request = try JSONDecoder().decode(Request<Ping>.self, from: data)
            inbound.continuation.yield(
                try JSONEncoder().encode(Ping.response(id: request.id, result: Empty())))
        case ReadResource.name:
            if let cancelOnSend {
                await cancelOnSend()
                throw MCPError.internalError("racing send failure")
            }
            if failSend { throw MCPError.internalError("test send failure") }
            if delayResourceSend {
                await withCheckedContinuation {
                    blockedResourceSend = $0
                    suspendedSendContinuation.yield(())
                }
            }
            resourceWireEvents.append("request")
            resourceCount += 1
            resourceContinuation.yield(
                try JSONDecoder().decode(Request<ReadResource>.self, from: data))
        case CancelledNotification.name:
            resourceWireEvents.append("cancel")
            cancellationCount += 1
            let message = try JSONDecoder().decode(Message<CancelledNotification>.self, from: data)
            if let id = message.params.requestId { cancellationContinuation.yield(id) }
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

private actor CancellationReference {
    private var request: Task<[Resource.Content], Error>?
    func set(_ request: Task<[Resource.Content], Error>) { self.request = request }
    func cancel() { request?.cancel() }
}
