# About this fork

**`ianegordon/swift-sdk` is a temporary integration fork of
[`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk).**

[Upstream](https://github.com/modelcontextprotocol/swift-sdk) is canonical. 

This is an UNOFFICIAL and hopefully short-lived fork.

This fork exists to unblock some downstream dependencies by pulling in 
some proposed fixes.

This fork carries those fixes, pre-integrated and tested together, so
that:

1. upstream pull requests stay open and mergeable exactly as submitted, and
2. downstream packages have a working alternative to depend on meanwhile.

This fork is intended to be temporary and archived ASAP. See [Sunset](#sunset).

## What is included

The `integration` branch is upstream `main` plus the pull requests below,
merged in the listed order. This table is the manifest: a PR is on
`integration` if and only if it is listed here.

| Order | Upstream PR | Fixes | Author | Head SHA merged | Status on `integration` | Notes |
| ----- | ----------- | ----- | ------ | --------------- | ----------------------- | ----- |
| 1 | [#264](https://github.com/modelcontextprotocol/swift-sdk/pull/264) | [#254](https://github.com/modelcontextprotocol/swift-sdk/issues/254), [#265](https://github.com/modelcontextprotocol/swift-sdk/issues/265) | jstar0 | `e14ef60` (branch `pr/264`) | merged | Stateless transport keys exchanges by a private id, so concurrent clients reusing a JSON-RPC id no longer displace each other's response waiter or HTTP context. |
| 1a | — (fork addition, offered upstream with #264) | verification of #254, #265 | ianegordon | `53bf923` (branch `pr/264-tests`, one tests-only commit on `e14ef60`) | merged | Regression suite driving two colliding exchanges through a real `Server`; fails on upstream `main`, passes with #264. |
| 2 | [#260](https://github.com/modelcontextprotocol/swift-sdk/pull/260) | [#255](https://github.com/modelcontextprotocol/swift-sdk/issues/255) | ianegordon | `b5da0ef` (branch `pr/260`); rebased onto #264 as `12b8c92` (branch `pr/260-on-264`) | merged | A cancelled request's HTTP exchange completes with a JSON-RPC error instead of hanging. The rebase routes the cancellation's `requestId` to the exchange id before forwarding it and adds a `Server` fallback to the id as given, so a cancelled handler still observes cancellation; ambiguous wire ids stay fail-closed. #264's byte-identical-forwarding assertion updated accordingly. |
| 3 | [#270](https://github.com/modelcontextprotocol/swift-sdk/pull/270) | [#285](https://github.com/modelcontextprotocol/swift-sdk/issues/285) | dariuscorvus | `0f38081` (branch `pr/270`); merged onto `integration` via `pr/270-on-integration`, adaptation in the merge resolution | merged | A cancellation arriving before the request's handler task is registered no longer falls through the gap; the built-in cancellation handler runs before logging can suspend. Adaptation: #264's handler-context id mapping kept alongside #270's early cancellation check; #270's `cancelRequest(id:)` is fed the routed id with the #260 fallback. Beyond the bug: duplicate outstanding request ids are rejected with `invalidRequest` (behavior change — inert on HTTP under #264, correct on single-client transports where a duplicate is a client error), and late responses from handlers that swallow cancellation are suppressed. Author's commit indentation is inconsistent with the file; left as authored, review feedback for upstream. |
| 4 | [#283](https://github.com/modelcontextprotocol/swift-sdk/pull/283) | [#282](https://github.com/modelcontextprotocol/swift-sdk/issues/282) | skirrellyjones | `c0ce9d6` (branch `pr/283`) | merged | `NetworkTransport` called `connection.cancel()` only on the reconnecting paths; with reconnection disabled a peer close left the socket in `CLOSE_WAIT`, leaking one file descriptor per client disconnect. Five lines, no adaptation. Tracking: fork issue #7. |
| 4a | — (fork addition, to be offered upstream with #283) | verification of #282 | ianegordon | `2e80db4` (branch `pr/283-tests`, one tests-only commit on `c0ce9d6`) | merged | Two mock-based `NetworkTransport` tests: with reconnection disabled, a receive failure and a graceful peer close must each finish the message stream and leave the connection cancelled. Fail on `pr/283~1` (mock left `.failed` / `.ready`), pass with #283. |
| 5 | [#221](https://github.com/modelcontextprotocol/swift-sdk/pull/221) | [#256](https://github.com/modelcontextprotocol/swift-sdk/issues/256) | piersdd | `42c30a1` (branch `pr/221`) | merged | `Client.connect` wrapped its receive loop in `repeat { … } while true`; once the transport's stream finished (peer gone, stdio subprocess exited) the loop re-entered the already-finished stream forever at 100% CPU. Flattened to the pattern `Server` uses. The removed EAGAIN retry arm was unreachable: `StdioTransport` retries EAGAIN inside its own read loop and never surfaces it through the stream. Maintainer-approved upstream. Supersedes #171 and #275. Tracking: fork issue #4. |
| 5a | — (fork addition, to be offered upstream with #221) | verification of #256 | ianegordon | `a50910c` (branch `pr/221-tests`, one tests-only commit on `42c30a1`) | merged | `MockTransport` counts `receive()` calls and can finish its stream without disconnecting; a connected `Client` whose stream ends must not request a second stream. Fails on `pr/221~1` (count reaches 2), passes with #221. |
| 6 | [#269](https://github.com/modelcontextprotocol/swift-sdk/pull/269) | — | shoemoney | `4a7d8ef` (branch `pr/269`) | merged | The everything-server listed `test://template/{id}` under `resources/list` and registered no `ListResourceTemplates` handler, so the template was advertised at the wrong endpoint and reachable at neither — `resources/templates/list` answered `-32601`. Spec-correct per the 2025-11-25 schema: `Resource.uri` is `format: uri`, `ResourceTemplate.uriTemplate` is `format: uri-template` (RFC 6570). Six lines, no adaptation. The PR's stated justification does not reproduce — `resources-list` passes on runner 0.1.15 (the version `ci.yml` pins) and 0.1.16 on every suite, because JSON Schema `format` is annotation-only by default — so this fixes a latent spec violation, not a failing test. Conformance harness only; the `MCP` library is untouched, so no downstream is affected either way. Tracking: fork issue #10. |
| 7 | [#276](https://github.com/modelcontextprotocol/swift-sdk/pull/276) | [#262](https://github.com/modelcontextprotocol/swift-sdk/issues/262) | nstrm | `f7077e0` (branch `pr/276`) | merged | `Client.Capabilities.experimental` was `[String: String]`, but the 2025-11-25 schema defines it as a map of arbitrary objects, so a ChatGPT-shaped `initialize` carrying `{"openai/visibility": {"enabled": true}}` failed to decode and the server answered `-32603` to a valid request. Reproduced on the wire before the merge and confirmed fixed after. **Source-breaking public type change:** `experimental` becomes `[String: Value]` — a dictionary literal with string values still compiles because `Value` is `ExpressibleByStringLiteral`, but a typed `[String: String]` variable and reading a value back as `String` do not. Entry 7a restores the first of those. Also adds `extensions` as `[String: Value]`, which is a **draft-schema** capability absent from 2025-11-25; an unmodeled key already decoded fine, so that half is a feature, not a fix. Ships its own two tests. Tracking: fork issue #11. |
| 7a | — (fork addition, to be offered upstream with #276) | source compatibility for #276 | ianegordon | `604afd2` (branch `pr/276-compat`, one commit on `f7077e0`) | merged | A deprecated `[String: String]` initializer for `Client.Capabilities`, so an existing typed variable still compiles behind a warning. `experimental` is required and undefaulted deliberately: with every parameter defaulted, overload resolution routes the bare `Client.Capabilities()` call to the compatibility initializer and warns on it, which is noise unrelated to `experimental`. Reading a value back as `String` is **not** restored — `experimental` is a stored property and Swift has no second property of the same name, so consumers that read values out still need updating. Follows the deprecated compatibility factories at `Sources/MCP/Server/Tools.swift:131`. |
| 8 | [#278](https://github.com/modelcontextprotocol/swift-sdk/pull/278) | [#277](https://github.com/modelcontextprotocol/swift-sdk/issues/277) | bitbemol | `af48e3f` (branch `pr/278`) | merged | `Value.init(from:)` treated any parseable data-URL-looking JSON string as `.data`, silently changing both the case and the string's spelling. Content explicitly tagged as MCP text was corrupted on round trip: `data:text/plain,Hello%20World` came back as `data:text/plain;base64,SGVsbG8gV29ybGQ=`. Generic JSON carries no discriminator and the spec tags content explicitly (`TextContent.type` is `const "text"`), so the decoder had no business guessing. The string branch now always produces `.string`; `Data.isDataURL(string:)` and `Data.parseDataURL(_:)` stay public for opt-in parsing and explicit `Value.data` encoding is unchanged. Verified by running the PR's own tests against the unpatched tree first — six of eight fail there, all eight pass after. **Behavior change, not a source break:** no API signature moves, so fork code calling `parseDataURL` explicitly compiles and behaves identically against upstream; no return trap. Caveat: `Value.data` is now round-trip-asymmetric — it encodes as a data URL but decodes back as `.string` — which the PR pins with a test. Nothing inside the SDK consumed the sniffing. The unrelated `NetworkTransport` capture-list hunk (`Task { @MainActor [self] in`) is behaviorally inert and warning-free on this toolchain; left as authored, review feedback for upstream. Tracking: fork issue #12. |
| 9 | [#266](https://github.com/modelcontextprotocol/swift-sdk/pull/266) | [#263](https://github.com/modelcontextprotocol/swift-sdk/issues/263) | jameswilson | `044e2b3` (branch `pr/266`) | merged | `StdioTransport.send` wrote straight to the descriptor, so two concurrent sends could interleave while one retried `EAGAIN` on a full pipe — the second message was spliced into the middle of the first, putting invalid JSON on the wire. Sends are now serialized FIFO through a task chain. Reproduced before the merge with the PR's own regression test: the small frame landed inside the large one, ahead of its terminator (`inserted [{"id":2}\n], removed [\n{"id":2}]`); one of seven stdio tests failed, all seven pass after. Private implementation only — a `lastSend` task handle and a private `write(_:)` — so no public API or wire-format change and no compatibility trap either way. **Upstream PR is a draft**, marked so because the author could not run the suite locally; pinning the exact SHA preserves reproducibility, but it may move if they revise it. **Lifecycle behavior, established by reading the merged code and recorded as accepted rather than fixed:** caller cancellation does not reach the send — `send` awaits an unstructured `Task`, which does not inherit cancellation — so a cancelled caller's message is still written in full. That is accidentally protective: `write(_:)`'s `EAGAIN` retry is `try await Task.sleep(for: .milliseconds(10))`, so naive cancellation propagation would throw *mid-frame* and leave a partial frame with no terminator, recreating the corruption this entry fixes. Any future cancellation policy must finish the frame or tear down the connection, never abandon a write in progress. Note #275 does **not** address this: it propagates cancellation through the client's request task, a different site from the transport's own unstructured tasks. Separately, `write(_:)` checks `isConnected` once on entry and never re-checks inside the retry loop, so an in-flight backpressured send does not terminate on `disconnect()` — it retries every 10ms until the reader drains. That loop is pre-existing and not introduced here, but serialization changes its blast radius: a stuck send now blocks every send queued behind it, and retains the chain, where previously other sends proceeded (corrupted). The trade made here is **frame corruption exchanged for head-of-line blocking**, which is the right direction — corrupt JSON breaks the session, a stalled write does not — but it is a trade, not a pure win. Tracking: fork issue #16. |
| 9a | — (fork addition, to be offered upstream with #266) | lifecycle gap left by #266 | ianegordon | `a0bac05` (branch `pr/266-lifecycle`, one commit on `044e2b3`) | merged | `write(_:)` checked `isConnected` once on entry and never again inside the `EAGAIN` retry loop, so a send parked on backpressure kept retrying every 10ms after `disconnect()` — and under entry 9's serialization everything queued behind it waited with it. Now re-checks after each backpressure sleep and throws `ENOTCONN`. Abandoning a partial frame is safe on teardown and **only** on teardown, which is why this is deliberately not the same as propagating caller cancellation into the write: that would abandon frames on a live connection and recreate the interleaving entry 9 fixes. Cancellation into the send therefore remains unaddressed, by design. The retry loop predates #266; only its blast radius changed. Test caveat: it drives a real 512KB write into an undrained pipe, disconnects, and races a 3s deadline — it passes with the change and does **not terminate** without it, so it is a positive check whose cleanup is best-effort. A send already parked in the retry loop cannot be reclaimed from the test, so on regression the expectation fails but the run may stall; failing cleanly would need a seam in the retry loop the transport does not expose. |
| 10 | [#275](https://github.com/modelcontextprotocol/swift-sdk/pull/275) (commit `8e36cfa` only) | — | robertoscipionecom | `f2f2888` (branch `pr/275-cherrypick`; upstream `8e36cfa` cherry-picked with `-x`) | merged | `Client.send` suspended on a checked continuation only a matching response could resume, and the request task was unstructured, so cancelling the caller never reached it — a caller that gave up stayed suspended until the server answered, which for a dead server is never. Three linked fixes: forward cancellation from `RequestContext.value` to the request task, call `cancelRequest` from the task cancellation handler, and remember ids cancelled before their continuation registered (the client-side mirror of entry 3's server-side gap). **Extracted, not merged whole — the one departure from "PRs are merged, never cherry-picked".** #275's other two commits, `40c5951` (loop termination) and `fded08a` (its test), duplicate entries 5 and 5a from #221; taking them conflicts in `Client.swift` and yields a duplicate `testMessageLoopStopsWhenStreamFinishes` declaration that does not compile. Verify fidelity by patch-id rather than by fetching a ref, since the SHA exists nowhere upstream: `git show f2f2888 | git patch-id --stable` equals `git show 8e36cfa | git patch-id --stable` (`e588896c…`), and the author is preserved (Roberto Scipione). The full PR head stays fetchable as branch `pr/275`. Because this is an intermediate commit of an open PR, re-check it still exists in the PR after any upstream revision — review will likely raise the `initialize` violation below. **Two defects came with this commit.** The first — a cancellation landing before the send completes was *notified before the request was sent* (observed wire order `notifications/cancelled(id), ping(id)`), so the peer discarded an unknown-id cancellation and then executed the request — is **fixed by entry 10b**; it was a behavior risk rather than bookkeeping, since a cancelled operation could still run. The second is **carried as accepted**: `cancelledBeforeRegistration` cannot distinguish "not registered yet" from "already completed", so cancelling a finished request leaves an entry until `disconnect()` — bounded per connection, and harmless in practice because ids are UUIDs so a stale marker cannot cancel a real request. Also still open: cancellation overtaking a send already suspended in `connection.send`. Both remaining items need the explicit request-state tracking (registration/sending/completion) that belongs upstream, not in a fork patch. Tracking: fork issue #15. |
| 10a | — (fork addition, to be offered upstream with #275) | spec compliance for entry 10 | ianegordon | `607c6dd` (branch `pr/275-compliance`, one commit on `f2f2888`) | merged | Entry 10 routes task cancellation through `cancelRequest`, which sends `notifications/cancelled` — and `initialize` reaches it via `connect()` → `_initialize()` → `sendAndAwait()` → `send()`, so cancelling a `connect()` under a deadline (the PR's own motivating case) violated *"The `initialize` request **MUST NOT** be cancelled by clients"* (2025-11-25, `basic/utilities/cancellation`). Enforced in **one** place rather than per path: the client records the in-flight initialize request's id and `cancelRequest` withholds the notification for it, so neither the public API nor the automatic handler can bypass it — an earlier revision guarded only the automatic path and left `client.cancelRequest(initializeID)` still emitting the notification. The caller is still released with `CancellationError` and a late response still ignored; only the notification is withheld, and every other method is unaffected. Two tests, one per path, each asserting the request was actually sent first, normalising JSON's escaped slashes before matching (an earlier version passed on the unguarded tree because `notifications\/cancelled` never matched), and bounding every wait with a deadline so a regression fails rather than hangs. Verified in both directions. |
| 10b | — (fork addition, to be offered upstream with #275) | first defect in entry 10 | ianegordon | `b7cb156` (branch `pr/275-lifecycle`, one commit on `607c6dd`) | merged | Entry 10's `addPendingRequest` resumes an already-cancelled continuation and returns early, but the early return only exits that function — the enclosing task still transmitted the request, so a cancellation went out *ahead of* the request it cancels and the peer executed a request whose caller had already been told it was cancelled. `addPendingRequest` now reports whether the request is pending and `send` skips transmission when it is not. A cancellation notification may still precede a request that is never sent; receivers may ignore unknown ids, which is strictly better than running a cancelled operation. Scope: this covers cancellation arriving *before registration*, not cancellation overtaking a send already suspended in `connection.send`. Test note: the window is unreachable from outside — 50 iterations of cancel-immediately-after-`Task` never once landed in it, so a naive test passes regardless. It is driven deterministically by cancelling from inside the same actor hop as `send`, before the queued registration task can run; technique borrowed from the #275 review probes. Verified in both directions, the failure quoting the inverted wire order. |

Candidates being evaluated, in intended order: easiest integration first,
then impact. Each has a tracking issue on this fork
(`Upstream PR#<n> - Merge`).

| Order | Upstream PR | Fixes | Author | Why | Notes |
| ----- | ----------- | ----- | ------ | --- | ----- |

None outstanding. Every PR triaged Merge has been integrated or declined.
The next candidates will come from the twelve upstream PRs triaged
Investigate, tracked in this fork's issues under the `investigate` label
(`Upstream PR#<n> - Investigate`); one moves into this table if investigation
promotes it to Merge.

Not included, and why:

| Upstream PR | Reason |
| ----------- | ------ |
| [#267](https://github.com/modelcontextprotocol/swift-sdk/pull/267) | Rejects a colliding id with 409. Mutually exclusive with #264, and a 409 fails legitimate traffic (independent clients commonly start their id sequence at the same value). #264 is carried instead. |
| [#227](https://github.com/modelcontextprotocol/swift-sdk/pull/227) | Relaxes `Value.init(_:)` from `Codable` to `Encodable`. Correct — the initializer's only use of `T` is `JSONEncoder.encode(_:)` — but it fixes no bug, and unlike every other entry carried here its absence upstream causes a compile error rather than a runtime fault. Code written against the fork with an `Encodable`-only type would not build on upstream unless #227 lands there, which would block the return this fork exists to make easy. Not worth that for an API loosening no downstream currently needs. |
| [#279](https://github.com/modelcontextprotocol/swift-sdk/pull/279) | Unable to test locally. Widens five `#if os(Linux)` guards in `HTTPClientTransport.swift` to `os(Linux) || os(Windows)`, fixing a real Windows build failure — `Package.swift` provides EventSource only on Apple platforms. The change is inert on macOS and Linux by inspection, but that it fixes Windows rests on the author's report; no Windows machine here and no Windows job in `ci.yml`. Windows is low priority for this fork's downstreams. Revisit if one targets Windows; carrying it later costs nothing, since the patch cannot make fork code upstream-incompatible. |

## Using the fork

Same package name, same `MCP` product and module, so switching is a URL
change and switching back is the same change reversed.

Pin an exact fork tag. Fork tags use SemVer prerelease form naming the
*next* upstream patch version — `0.12.2-ianegordon.N` while the base is
`0.12.1` — because a prerelease identifier denotes a version that precedes
the one it names, and this content is "0.12.1 plus fixes on the way to
0.12.2". The identifier makes a fork tag impossible to mistake for an
upstream release, and it sorts correctly before a real `0.12.2` if upstream
ships one. `N` increments per fork tag on the same base:

```swift
.package(url: "https://github.com/ianegordon/swift-sdk.git", exact: "0.12.2-ianegordon.9")
```

Two Swift Package Manager facts to know:

- A `from:` or `upToNextMajor` range does not select prerelease versions:
  the package manager only considers prereleases when a requirement's own
  bounds carry prerelease identifiers, and an `exact:` requirement does
  when its version does (`VersionSetSpecifier.supportsPrereleases`,
  <https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageGraph/VersionSetSpecifier.swift>).
  An `exact:` pin is therefore the way to take a fork tag.
- Depending on the `integration` branch directly works but is not
  reproducible; tags are the contract, the branch is where they come from.

Tags are cut only from `integration`, only after the full test suite passes
on it, and each tag's notes list the manifest as of that tag.

## Branch layout

| Branch | Role | Rewritten? |
| ------ | ---- | ---------- |
| `main` | Exact mirror of upstream `main`. Fast-forward only. Never carries a fork commit. | never |
| `pr/<n>` | Mirror of upstream `refs/pull/<n>/head` at the SHA recorded in the manifest. Author's commits untouched. | only to track the upstream PR |
| `pr/<n>-on-<base>` | An upstream PR rebased or conflict-resolved to sit on another included PR. The author's commits stay intact; the adaptation is a separate commit attributed to whoever did it. | as needed |
| `pr/<n>-cherrypick` | One commit extracted unmodified from a PR whose other commits the fork already carries (see **Inclusion policy**). Based on `integration`, not on `pr/<n>`: it is upstream's own code, so there is nothing to offer upstream. `pr/<n>` stays pushed alongside it. | only to re-extract after an upstream revision |
| `pr/<n>-<topic>` | A fork addition stacked directly on `pr/<n>` (for example `pr/264-tests`): one clean commit, touching only what upstream will want, so it can be offered as a PR against the author's branch, as a follow-up upstream PR once `<n>` merges, or cherry-picked — the same commit serves all three. | only to rebase onto a moved `pr/<n>` |
| `fix/<issue>-…` | This fork owner's own upstream-facing branches (for example `fix/254-response-waiter-collision`, `fix/255-cancellation-hang`). Each backs an open upstream PR and is kept mergeable against upstream `main`. | only to rebase onto a moved upstream `main` |
| `integration` | `main` + the manifest, merged in order. **Default branch.** Merge-only: new PRs and `upstream/main` are merged in; it is not force-pushed. Protected against deletion and force pushes. | no (see below) |
| `integration-next` | Scratch rebuild of `integration` from the manifest, used to check that the merge-only branch still equals a clean rebuild. Disposable. | freely |

Conflicts between included PRs are resolved only in `pr/<n>-on-<base>`
branches and, through them, on `integration`. The upstream-facing branches
never absorb each other, which is what keeps every upstream PR mergeable as
submitted.

If a rebuild ever differs materially from the merge-only `integration` —
for example an included PR was force-pushed upstream and its adaptation had
to change — `integration` is replaced wholesale, a tag is cut, and the
change is announced in the fork's issues. Consumers pinned to tags are
unaffected.

## Inclusion policy

- **Bug fixes first.** Behavior changes and features are included only when
  a downstream depending on this fork needs them, and the reason is recorded
  in the manifest. Every addition beyond upstream makes the fork stickier,
  and the goal is to disappear.
- **One fix per problem.** Where two upstream PRs solve the same defect
  differently, one is chosen and the choice is recorded with its reasoning
  (see #264 versus #267 above).
- **Nothing lands without the full suite passing on the combined branch.**
  Where a PR lacks tests, regression tests are added on a fork branch and
  offered upstream.
- **Authorship is preserved.** PRs are merged, never cherry-picked and
  edited. Author, committer, and `Signed-off-by` trailers stay as the author
  wrote them. Contributions were submitted to upstream under Apache-2.0
  §5, which is what permits carrying them here.
- **Extraction is a bounded exception.** A single commit may be taken from a
  PR instead of merging the PR head, but only when every skipped commit is
  already carried by another manifest entry, and only unmodified: cherry-pick
  with `-x`, keep the author, and record in the manifest that the fork SHA's
  `git patch-id --stable` equals the upstream commit's. Verification shifts
  from "fetch the ref and diff" to comparing patch-ids, so both SHAs go in the
  manifest and the full PR head stays pushed as `pr/<n>`. The reason for the
  bound: extraction turns the fork from a mirror of upstream proposals into a
  curated patch set, which is harder to hand back. It is also fragile — an
  intermediate commit of an open PR can vanish under a rebase or squash, so
  re-check it after any upstream revision. Entry 10 is the only use to date;
  prefer a merge plus a stacked follow-up wherever it is possible.
- **Authors are told.** Each included PR gets one comment saying it is
  carried here, at which commit, and that it will be dropped once merged
  upstream.

## Reporting problems

Report defects **upstream first**, then, if the fork needs to track it, open
a fork issue that links the upstream one. Fixes should be submitted as
**upstream pull requests**; this fork picks them up from there. Please do 
NOT open PRs against ianegordon/swift-sdk directly. Problems in the
integration itself (a bad merge, a broken tag) are fork issues.

## Sunset

- As each included PR merges upstream, it is dropped from the manifest and
  `integration` is rebuilt on the new upstream `main`, so the fork shrinks
  on its own.
- When the manifest is empty and the remaining PRs have a path, a final tag 
  is cut, this file and the README banner are updated to 
  "superseded — use upstream", and the repository is **archived**, not deleted. 
  Archived repositories stay resolvable, so no consumer's `Package.resolved` 
  breaks.

## Maintenance procedure

Until this is scripted, the steps are manual and this file is the record.

1. `git fetch upstream && git push origin upstream/main:main` — refresh the
   mirror (fast-forward only).
2. For each manifest row in order: fetch `refs/pull/<n>/head`, confirm the
   SHA matches the manifest (record a change if the author pushed), and
   merge `pr/<n>` or its `-on-<base>` adaptation into `integration`.
3. `swift test` on `integration`; nothing is tagged on a red suite.
4. Tag `<next upstream patch>-ianegordon.<N>` on `integration` as an
   annotated tag with the manifest in the tag message.
5. Update this file's manifest table.
