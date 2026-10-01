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
    /// No marker is registered for the `markerId` the call supplied.
    static let markerNotFound = "MARKER_NOT_FOUND"
    /// A required argument was missing or the wrong type.
    static let invalidArgument = "INVALID_ARGUMENT"
    /// A native operation failed at runtime (its `Error` is forwarded too).
    static let operationFailed = "OPERATION_FAILED"
    /// `create` could not place the native map in the web view (no container for
    /// the element turned up), or the map was destroyed before it mounted.
    static let mountFailed = "MOUNT_FAILED"
}
