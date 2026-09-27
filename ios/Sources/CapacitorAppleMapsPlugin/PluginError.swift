import Foundation

// MARK: - Rejection codes
//
// Stable, machine-readable codes passed as the second argument to
// `call.reject(_:_:)`. They reach JS as the `code` property of the rejected
// error, so host apps can branch on them instead of matching message strings
// (which are for humans and may change). Keep these values stable.

enum PluginError {
    /// No map is registered for the `id` the call supplied.
    static let mapNotFound = "MAP_NOT_FOUND"
    /// A required argument was missing or the wrong type.
    static let invalidArgument = "INVALID_ARGUMENT"
    /// A native operation failed at runtime (its `Error` is forwarded too).
    static let operationFailed = "OPERATION_FAILED"
}
