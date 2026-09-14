# PicoCore lifecycle additions to Ian’s integration

Baseline: `ianegordon/swift-sdk` exact tag `0.12.2-ianegordon.11`, commit
`296055f4f5e14ce1b161fb7b26219cad288b3a31`. `FORK.md` describes that integrated
baseline. PicoCore issue180 and dependency PR185 record why it is selected.
This branch preserves that implementation, including its continuation-based
request registration and RequestContext cancellation forwarding.

The extra client changes address failures reproduced against that exact tag:

- Check cancellation at send entry and when awaiting a result, including errors.
- Track requests awaiting registration so cancellation of completed/unknown IDs
  cannot create permanent markers. Both single and batch requests register issuance.
- Clean up failed/cancelled handshakes and reject stale handshake success.
- Fence queued request work and handshakes across disconnect/reconnect generations.

Local runtime: baseline587tests43suites pass; patched599tests44suites pass,
including12 lifecycle probes. Regressions cover pending cancellation,
independent requests, late responses, cancelled entry, handshake cancellation,
reconnect overlap, send errors, batches, and32completed/cancelled requests without
retained markers. The tests observe private marker state from the Client actor;
they add no public diagnostic API.

## Cancellation limits

Cancellation completes the local waiter; remote cancellation remains advisory.
A transport send can suspend before dispatch or while awaiting the entire HTTP
response. The cancellation notification is therefore sent immediately after
local cancellation for a registered request. It can overtake a request that has
not reached the peer. Waiting for send to return would prevent notification
during active HTTP server work, so this branch deliberately does not do that.
The suspended-send test fixes this contract in place: caller and independent
request proceed before the original send is released. No remote non-execution
or rollback guarantee is claimed.

Batch cancellation keeps its existing local completion behavior. Batch wire
filtering/automatic task cancellation remain outside this change. Handshake
cleanup applies to the SDK Client's connection attempt; PicoCore still owns its
coalesced connection tasks and must test waiter/sign-out ownership separately.

A separate commit reuses the first-GET SSE delivery fix after reproducing it
against this integration: the deterministic test fails three assertions before
the fix (only a priming event arrives), and passes after. The conformance CI
also timed out waiting for a sampling response (39/40 passed). Already-stored
server messages are now delivered before the first GET priming cursor, using
the existing event store. No new queue or scheduler state is introduced.
The final transport change passes38focusedtests across transport/lifecycle suites;
the599-test full run above preceded this additional regression test.

The CI workflow targets this integration base and uses macos-15/Xcode16.4 for
Swift6.1 with a compatible Apple SDK; Linux retains Swift6.1. Return to an
official release only when the relied-on integration and lifecycle fixes are
present and the same regressions pass. No automatic upstream posting or merging.
