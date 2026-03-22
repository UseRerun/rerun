import Foundation
import RerunCore
import MLXLLM
import MLXLMCommon
import os

private let logger = Logger(subsystem: "com.rerun", category: "ChatEngine")

typealias ChatSummarySynthesizer = @Sendable (ChatSummaryRequest) async -> String?

struct ChatSummaryRequest: Sendable {
    let rawQuery: String
    let appFilter: String?
    let appSummary: [String]
    let workspaces: [String]
    let facts: [ActivityFact]
    let captureContext: String?

    var debugInfo: SummaryDebugInfo {
        SummaryDebugInfo(
            appFilter: appFilter,
            appSummary: appSummary,
            workspaces: workspaces,
            facts: facts.map(\.text)
        )
    }

    init(parsed: ParsedQuery, summary: ActivitySummary, captureContext: String? = nil) {
        self.rawQuery = parsed.rawQuery
        self.appFilter = parsed.appFilter
        self.appSummary = summary.appFrequency.map { "\($0.appName) (\($0.count))" }
        self.workspaces = summary.workspaces
        self.facts = summary.facts
        self.captureContext = captureContext
    }
}

struct ChatEngineResponse: Sendable {
    let content: String
    let sources: [SourceReference]
    let summaryDebug: SummaryDebugInfo?
}

actor ChatEngine {
    private let service: SearchService
    private let summarySynthesizer: ChatSummarySynthesizer?

    init(db: DatabaseManager, modelManager: ModelManager) {
        self.service = SearchService(db: db)
        self.summarySynthesizer = { request in
            await ChatEngine.synthesizeWithMLX(request: request, modelManager: modelManager)
        }
    }

    init(db: DatabaseManager, summarySynthesizer: ChatSummarySynthesizer?) {
        self.service = SearchService(db: db)
        self.summarySynthesizer = summarySynthesizer
    }

    func process(_ message: String) async -> ChatEngineResponse {
        let response: SearchResponse
        do {
            response = try await service.search(SearchRequest(query: message, limit: 30))
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            return ChatEngineResponse(
                content: "Something went wrong searching your captures.",
                sources: [],
                summaryDebug: nil
            )
        }

        guard !response.hits.isEmpty else {
            return ChatEngineResponse(
                content: "Couldn't find anything matching that. Try a broader question.",
                sources: [],
                summaryDebug: nil
            )
        }

        return await buildResponse(from: response)
    }

    func process(parsed: ParsedQuery) async -> ChatEngineResponse {
        let response: SearchResponse
        do {
            response = try await service.search(SearchRequest(
                query: parsed.rawQuery,
                app: parsed.appFilter,
                since: parsed.since,
                limit: 30,
                parsedQuery: parsed
            ))
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            return ChatEngineResponse(
                content: "Something went wrong searching your captures.",
                sources: [],
                summaryDebug: nil
            )
        }

        guard !response.hits.isEmpty else {
            return ChatEngineResponse(
                content: "Couldn't find anything matching that. Try a broader question.",
                sources: [],
                summaryDebug: nil
            )
        }

        return await buildResponse(from: response)
    }

    // MARK: - Response Building

    private func buildResponse(from response: SearchResponse) async -> ChatEngineResponse {
        let sources = response.hits.map { hit in
            SourceReference(
                captureId: hit.capture.id,
                appName: hit.capture.appName,
                timestamp: hit.capture.timestamp,
                windowTitle: hit.capture.windowTitle,
                url: hit.capture.url,
                snippet: hit.snippet
            )
        }

        let content: String
        var summaryDebug: SummaryDebugInfo? = nil

        if let summary = response.summary {
            let captures = response.hits.map(\.capture)
            let context = SearchService.buildContext(from: captures)
            let request = ChatSummaryRequest(
                parsed: response.parsed,
                summary: summary,
                captureContext: context
            )
            summaryDebug = request.debugInfo
            content = await formatSummary(request, captureCount: response.hits.count)
        } else {
            content = formatSearchResults(response)
        }

        return ChatEngineResponse(content: content, sources: sources, summaryDebug: summaryDebug)
    }

    // MARK: - Formatting

    private func formatSearchResults(_ response: SearchResponse) -> String {
        let captures = response.hits.map(\.capture)
        var lines = ["Found \(captures.count) result\(captures.count == 1 ? "" : "s"):"]
        for (i, capture) in captures.enumerated() {
            let time = formatTimestamp(capture.timestamp)
            var entry = "\(i + 1). \(time) — \(capture.appName)"
            if let title = capture.windowTitle {
                entry += " — \(title)"
            }
            lines.append(entry)
        }
        return lines.joined(separator: "\n")
    }

    private func formatSummary(_ request: ChatSummaryRequest, captureCount: Int) async -> String {
        if let synthesized = await synthesizeSummary(for: request), !synthesized.isEmpty {
            return synthesized
        }

        return formatFallbackSummary(request, captureCount: captureCount)
    }

    private func synthesizeSummary(for request: ChatSummaryRequest) async -> String? {
        guard let summarySynthesizer else { return nil }
        // Need either capture context (for MLX) or facts (for fallback)
        guard request.captureContext != nil || !request.facts.isEmpty else { return nil }
        return await summarySynthesizer(request)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatFallbackSummary(_ request: ChatSummaryRequest, captureCount: Int) -> String {
        var lines = ["Recent activity\(request.appFilter.map { " in \($0)" } ?? ""):"]

        if !request.appSummary.isEmpty {
            lines.append("Apps: \(request.appSummary.joined(separator: ", "))")
        }

        if !request.workspaces.isEmpty {
            lines.append("Workspaces: \(request.workspaces.prefix(5).joined(separator: ", "))")
        }

        if !request.facts.isEmpty {
            lines.append("Observed work:")
            for fact in request.facts.prefix(4) {
                lines.append("- \(fact.text)")
            }
            return lines.joined(separator: "\n")
        }

        lines.append("Found \(captureCount) recent capture\(captureCount == 1 ? "" : "s").")
        return lines.joined(separator: "\n")
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else {
            return String(iso.prefix(16))
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - LLM Synthesis

    private static func synthesizeWithMLX(request: ChatSummaryRequest, modelManager: ModelManager) async -> String? {
        // Non-blocking: if model isn't downloaded yet, return nil so fallback facts are shown
        guard let container = await modelManager.getContainerIfReady() else {
            return nil
        }
        guard let context = request.captureContext, !context.isEmpty else {
            return nil
        }

        do {
            let instructions = """
                You answer questions about the user's computer activity based ONLY on the data below.

                RULES:
                1. Answer ONLY what was asked — don't summarize everything.
                2. Each entry shows the app in brackets like [time, AppName]. Focus on activities relevant to the question.
                3. Describe what was DONE, not UI chrome that was merely visible on screen. Ignore sidebar labels, empty states, notification badges.
                4. Use natural time references: "Around 2pm...", "Earlier today..."
                5. Never say "capture", "screenshot", "frame", "OCR", or "screen recording".
                6. Write 2-3 sentences, conversationally. Not a bulleted list.
                7. Start with the answer immediately — no preamble like "Based on the data" or "Here's what I found".
                8. If the data doesn't clearly answer the question, say so honestly.

                ACTIVITY DATA:
                \(context)
                """

            let params = GenerateParameters(maxTokens: 512)
            let session = ChatSession(container, instructions: instructions, generateParameters: params)

            var response = ""
            for try await token in session.streamResponse(to: request.rawQuery) {
                response.append(token)
            }

            // Clean special tokens
            response = response
                .replacingOccurrences(of: "<end_of_turn>", with: "")
                .replacingOccurrences(of: "<start_of_turn>", with: "")
                .replacingOccurrences(of: "<bos>", with: "")
                .replacingOccurrences(of: "<eos>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return response.isEmpty ? nil : response
        } catch {
            logger.warning("MLX synthesis failed: \(error.localizedDescription)")
            return nil
        }
    }
}
