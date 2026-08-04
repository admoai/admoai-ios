import Testing

/// Parent suite for **every** test that drives ``MockURLProtocol``.
///
/// `MockURLProtocol` records requests and holds its stub in `static` state, because a
/// `URLProtocol` is instantiated by `URLSession` and cannot be handed per-test context. Swift
/// Testing runs tests in parallel by default, so two tests sharing that state race: one test's
/// `reset()` wipes another's captures mid-flight, and assertions then see a *different* test's
/// requests. `.serialized` on a single suite is not enough — it orders tests *within* that
/// suite while still letting sibling suites run alongside it.
///
/// Nesting every `MockURLProtocol` consumer under this one serialized suite closes that:
/// `.serialized` applies to the whole subtree, so no two of them ever run concurrently.
/// Child suites are attached from their own files via `extension MockNetworkTests { … }`.
///
/// **Add new `MockURLProtocol` tests here, not as a top-level suite** — a top-level suite
/// would race with these and fail intermittently in a way that looks like an SDK bug.
@Suite(.serialized)
struct MockNetworkTests {}
