// AccessibilityPoller.swift
//
// Adapted for SimPilot from AXe (https://github.com/cameroncooke/AXe),
// origin: Sources/AXe/Utilities/AccessibilityPoller.swift — MIT License
// (Copyright (c) 2025 Cameron Cooke; see THIRD_PARTY_LICENSES.md).
//
// The polling control flow is preserved exactly: fetch roots, try to resolve,
// and on a not-found error keep retrying at `pollInterval` until `waitTimeout`
// elapses. SimCore stays Foundation-only, so AXe's FB-coupled
// `AccessibilityFetcher` and its `AxeLogger` dependency are removed: the caller
// supplies the roots through an async `rootsFetcher` closure (the driver layer
// wires this to the native describe-ui pass), and the element model is
// SimCore.AXNode.

import Foundation

public enum AccessibilityPoller {
    /// Resolve a selector to a tap target, polling until it appears or the
    /// timeout elapses. `rootsFetcher` supplies a fresh accessibility tree on
    /// each attempt.
    public static func resolveTapWithPolling(
        query: AccessibilityQuery,
        waitTimeout: TimeInterval,
        pollInterval: TimeInterval,
        elementType: String? = nil,
        rootsFetcher: () async throws -> [AXNode]
    ) async throws -> TapResolution {
        try await pollForResolution(
            query: query,
            waitTimeout: waitTimeout,
            pollInterval: pollInterval,
            elementType: elementType,
            resolver: AccessibilityTargetResolver.resolveTap,
            rootsFetcher: rootsFetcher
        )
    }

    /// Resolve a selector to a match, polling until it appears or the timeout
    /// elapses.
    public static func resolveElementWithPolling(
        query: AccessibilityQuery,
        waitTimeout: TimeInterval,
        pollInterval: TimeInterval,
        elementType: String? = nil,
        rootsFetcher: () async throws -> [AXNode]
    ) async throws -> AccessibilityMatch {
        try await pollForResolution(
            query: query,
            waitTimeout: waitTimeout,
            pollInterval: pollInterval,
            elementType: elementType,
            resolver: AccessibilityTargetResolver.resolveElement,
            rootsFetcher: rootsFetcher
        )
    }

    private static func pollForResolution<T>(
        query: AccessibilityQuery,
        waitTimeout: TimeInterval,
        pollInterval: TimeInterval,
        elementType: String?,
        resolver: ([AXNode], AccessibilityQuery, String?) throws -> T,
        rootsFetcher: () async throws -> [AXNode]
    ) async throws -> T {
        let roots = try await rootsFetcher()
        do {
            return try resolver(roots, query, elementType)
        } catch let error as ElementResolutionError where error.isNotFound && waitTimeout > 0 {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(waitTimeout)

            var lastError = error
            while clock.now < deadline {
                try await Task.sleep(for: .seconds(pollInterval))

                let freshRoots = try await rootsFetcher()
                do {
                    return try resolver(freshRoots, query, elementType)
                } catch let retryError as ElementResolutionError where retryError.isNotFound {
                    lastError = retryError
                    continue
                }
            }

            throw lastError
        }
    }
}
