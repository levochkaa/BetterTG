// TDClientDemoResponses.swift

#if DEBUG
import Foundation

/// What a launch-only demo answers in place of TDLib, for the requests `script/generate_tdlib_client_compat.py` lists.
/// Nil outside the demo and for a request the demo leaves to TDLib, which refuses it without a session.
enum TDClientDemoResponses {
    nonisolated(unsafe) static var answer: (@Sendable (_ request: String, _ arguments: [String: Any]) -> Any?)?
}
#endif
