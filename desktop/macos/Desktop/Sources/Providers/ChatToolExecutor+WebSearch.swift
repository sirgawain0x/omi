import Foundation

extension ChatToolExecutor {
  /// Typed-chat public-web lookup. Advertised on `desktop_chat`; authorized
  /// `main_chat` and `floating_chat` commands route here via surface-aware
  /// executor resolution so they never hit the voice-only realtime invocation map.
  static func executeWebSearch(
    _ arguments: [String: Any],
    expectedOwnerID: String?,
    api: APIClient = .shared,
    customBaseURL: String? = nil
  ) async -> String {
    guard !AppState.isPaywalledEffective else {
      return "Web search is only available on paid Omi plans."
    }
    guard let query = arguments["query"] as? String, !query.isEmpty else {
      return "Error: query is required"
    }
    guard let expectedOwnerID else { return authorizedOwnerChangedResult() }
    let scope = RealtimePublicWebSearchScope(toolValue: arguments["scope"])
    let prompts = RealtimeHubTools.publicWebSearchPrompts(query: query, scope: scope)
    do {
      if prompts.count == 1 {
        return try await api.searchPublicWebForVoice(
          query: prompts[0],
          expectedOwnerID: expectedOwnerID,
          customBaseURL: customBaseURL)
      }
      async let primary = try? await api.searchPublicWebForVoice(
        query: prompts[0],
        expectedOwnerID: expectedOwnerID,
        customBaseURL: customBaseURL,
        includeSourceEvidence: true)
      async let corroborating = try? await api.searchPublicWebForVoice(
        query: prompts[1],
        expectedOwnerID: expectedOwnerID,
        customBaseURL: customBaseURL,
        includeSourceEvidence: true)
      async let exactMatch = try? await api.searchPublicWebForVoice(
        query: prompts[2],
        expectedOwnerID: expectedOwnerID,
        customBaseURL: customBaseURL,
        includeSourceEvidence: true)
      let (primaryAnswer, corroboratingAnswer, exactMatchAnswer) = await (
        primary, corroborating, exactMatch
      )
      guard
        let combined = RealtimeHubTools.combinedHistoricalWebEvidence(
          primary: primaryAnswer,
          corroborating: corroboratingAnswer,
          exactMatch: exactMatchAnswer)
      else {
        return "The web lookup failed. Please try again."
      }
      return combined
    } catch {
      return "The web lookup failed. Please try again."
    }
  }
}
