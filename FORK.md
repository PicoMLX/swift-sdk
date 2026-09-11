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

Candidates being evaluated, in intended order. All of these applied cleanly to
`integration` as of 2026-09-10 and none touches a file the fork has already
adapted; the order is easiest integration first, then impact. Each has a
tracking issue on this fork (`Upstream PR#<n> - Merge`).

| Order | Upstream PR | Fixes | Author | Why | Notes |
| ----- | ----------- | ----- | ------ | --- | ----- |
| 6 | [#227](https://github.com/modelcontextprotocol/swift-sdk/pull/227) | — | samkudr | `Value.init(_:)` requires `Codable` where only `Encodable` is used. | 3 lines, 1 file. Strictly loosening. Before #278, which also touches `Value.swift`. |
| 7 | [#279](https://github.com/modelcontextprotocol/swift-sdk/pull/279) | — | onetamer | Windows builds fail: `EventSource` is imported behind `#if !os(Linux)` but only provided on Apple platforms. | 5 lines, 1 file. No behavior change on platforms that built before. |
| 8 | [#269](https://github.com/modelcontextprotocol/swift-sdk/pull/269) | — | shoemoney | Conformance server lists a resource template under `resources/list` with an invalid URI. | 6 lines, 1 file, test harness only. |
| 9 | [#276](https://github.com/modelcontextprotocol/swift-sdk/pull/276) | [#262](https://github.com/modelcontextprotocol/swift-sdk/issues/262) | nstrm | Servers cannot decode ChatGPT's `initialize`: `Client.Capabilities.experimental` is `[String: String]` where the spec allows arbitrary objects. | 62 lines, 2 files. **Public type change** (`experimental` becomes `[String: Value]`, `extensions` added); source-compatible for string literals. Record in the manifest. |
| 10 | [#278](https://github.com/modelcontextprotocol/swift-sdk/pull/278) | [#277](https://github.com/modelcontextprotocol/swift-sdk/issues/277) | bitbemol | `Value.init(from:)` silently turns any data-URL-looking string into `.data`, altering content on round trip. | 185 lines, 3 files. **Behavior change** toward correctness; explicit `Value.data` and the data-URL helpers remain. Last because it is the largest and the second edit to `NetworkTransport.swift` and `Value.swift` in the batch. |

Not included, and why:

| Upstream PR | Reason |
| ----------- | ------ |
| [#267](https://github.com/modelcontextprotocol/swift-sdk/pull/267) | Rejects a colliding id with 409. Mutually exclusive with #264, and a 409 fails legitimate traffic (independent clients commonly start their id sequence at the same value). #264 is carried instead. |

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
.package(url: "https://github.com/ianegordon/swift-sdk.git", exact: "0.12.2-ianegordon.5")
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
