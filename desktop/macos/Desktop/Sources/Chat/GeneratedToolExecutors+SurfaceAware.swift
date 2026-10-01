import Foundation

extension GeneratedToolExecutors {
  /// Resolves the physical Swift executor for an authorized tool on a concrete
  /// surface. Most tools have one executor; `web_search` is dual-surface:
  /// typed chat must use `chatToolExecutor` (no voice invocation envelope),
  /// while realtime voice keeps `realtimeHub` for acknowledgements, historical
  /// multi-pass, and turn evidence.
  static func executor(
    for tool: GeneratedSwiftTool,
    surfaceKind: String
  ) -> GeneratedSwiftToolExecutor? {
    if tool == .webSearch, usesTypedChatPublicWebExecutor(surfaceKind: surfaceKind) {
      return .chatToolExecutor
    }
    return executorByTool[tool]
  }

  /// Desktop typed-chat coordinator surfaces that advertise `web_search` through
  /// the pi-mono lane (see `isToolAvailableForContext` / `typedChatCoordinatorOnly`).
  private static func usesTypedChatPublicWebExecutor(surfaceKind: String) -> Bool {
    switch surfaceKind {
    case "main_chat", "floating_chat":
      return true
    default:
      return false
    }
  }
}
