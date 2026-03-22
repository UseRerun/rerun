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

struct ChatStreamResponse: Sendable {
    let sources: [SourceReference]
    let summaryDebug: SummaryDebugInfo?
    let fallbackContent: String?
    let recoveryContent: String?
    let tokenStream: AsyncThrowingStream<String, Error>?
}

actor ChatEngine {
    private let service: SearchService
    private let summarySynthesizer: ChatSummarySynthesizer?
    private let modelManager: ModelManager?

    init(db: DatabaseManager, modelManager: ModelManager) {
        self.service = SearchService(db: db)
        self.modelManager = modelManager
        self.summarySynthesizer = { request in
            await ChatEngine.synthesizeWithMLX(request: request, modelManager: modelManager)
        }
    }

    init(db: DatabaseManager, summarySynthesizer: ChatSummarySynthesizer?) {
        self.service = SearchService(db: db)
        self.modelManager = nil
        self.summarySynthesizer = summarySynthesizer
    }

    // MARK: - Non-streaming (used by CLI and tests)

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

    // MARK: - Streaming (used by chat UI)

    func processStreaming(_ message: String) async -> ChatStreamResponse {
        let response: SearchResponse
        do {
            response = try await service.search(SearchRequest(query: message, limit: 10))
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            return ChatStreamResponse(
                sources: [],
                summaryDebug: nil,
                fallbackContent: "Something went wrong searching your captures.",
                recoveryContent: "Something went wrong searching your captures.",
                tokenStream: nil
            )
        }

        guard !response.hits.isEmpty else {
            return ChatStreamResponse(
                sources: [],
                summaryDebug: nil,
                fallbackContent: "Couldn't find anything matching that. Try a broader question.",
                recoveryContent: "Couldn't find anything matching that. Try a broader question.",
                tokenStream: nil
            )
        }

        let sources = buildSources(from: response)

        guard let summary = response.summary else {
            return ChatStreamResponse(
                sources: sources,
                summaryDebug: nil,
                fallbackContent: formatSearchResults(response),
                recoveryContent: formatSearchResults(response),
                tokenStream: nil
            )
        }

        let captures = response.hits.map(\.capture)
        let context = SearchService.buildContext(from: captures, maxTextLength: 1000)
        let request = ChatSummaryRequest(parsed: response.parsed, summary: summary, captureContext: context)
        let summaryDebug = request.debugInfo
        let recoveryContent = formatFallbackSummary(request, captureCount: response.hits.count)

        // Try MLX streaming
        guard let modelManager = self.modelManager,
              let container = await modelManager.getContainerIfReady(),
              let captureContext = request.captureContext, !captureContext.isEmpty else {
            return ChatStreamResponse(
                sources: sources,
                summaryDebug: summaryDebug,
                fallbackContent: recoveryContent,
                recoveryContent: recoveryContent,
                tokenStream: nil
            )
        }

        let query = request.rawQuery
        let tokenStream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task.detached {
                do {
                    let instructions = ChatEngine.buildInstructions(context: captureContext)
                    let params = GenerateParameters(maxTokens: 512)
                    let session = ChatSession(container, instructions: instructions, generateParameters: params)

                    for try await token in session.streamResponse(to: query) {
                        if Task.isCancelled { break }
                        let cleaned = ChatEngine.cleanToken(token)
                        if !cleaned.isEmpty {
                            continuation.yield(cleaned)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // 30-second timeout
            let timeout = Task.detached {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled {
                    task.cancel()
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                timeout.cancel()
            }
        }

        return ChatStreamResponse(
            sources: sources,
            summaryDebug: summaryDebug,
            fallbackContent: nil,
            recoveryContent: recoveryContent,
            tokenStream: tokenStream
        )
    }

    // MARK: - Response Building

    private func buildSources(from response: SearchResponse) -> [SourceReference] {
        response.hits.map { hit in
            SourceReference(
                captureId: hit.capture.id,
                appName: hit.capture.appName,
                timestamp: hit.capture.timestamp,
                windowTitle: hit.capture.windowTitle,
                url: hit.capture.url,
                snippet: hit.snippet
            )
        }
    }

    private func buildResponse(from response: SearchResponse) async -> ChatEngineResponse {
        let sources = buildSources(from: response)

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

    private static func buildInstructions(context: String) -> String {
        """
        You answer questions about the user's computer activity based ONLY on the data below.

        IMPORTANT: Each entry's Content field may contain text from MULTIPLE apps that were visible on screen at the same time. The AppName in brackets is the FOCUSED app — but the Content may also include text from background windows, notifications, sidebars, and other apps. Be very careful to only reference content that clearly belongs to the focused app mentioned in brackets.

        RULES:
        1. Answer ONLY what was asked — don't summarize everything.
        2. Each entry shows the app in brackets like [time, AppName]. ONLY use entries from apps relevant to the question. If the user asks about texting, only use Messages entries. If they ask about browsing, only use browser entries. Ignore entries from unrelated apps completely.
        3. Within each entry, ignore content that clearly belongs to OTHER apps (email notifications, calendar alerts, unrelated app sidebars). Only reference content that logically belongs to the focused app.
        4. Use natural time references: "Around 2pm...", "Earlier today..."
        5. Never say "capture", "screenshot", "frame", "OCR", or "screen recording".
        6. Use short paragraphs. For broad questions like "what was I working on", group by topic or app with line breaks between them. Keep each group to 1-2 sentences.
        7. Start with the answer immediately — no preamble like "Based on the data" or "Here's what I found".
        8. ACCURACY IS CRITICAL. Only state things you can directly see in the data. Never combine information from different apps or entries to invent a narrative. If the data is unclear or doesn't answer the question, say "I'm not sure based on what I can see" rather than guessing.

        ACTIVITY DATA:
        \(context)
        """
    }

    private static func cleanToken(_ token: String) -> String {
        token
            .replacingOccurrences(of: "<end_of_turn>", with: "")
            .replacingOccurrences(of: "<start_of_turn>", with: "")
            .replacingOccurrences(of: "<bos>", with: "")
            .replacingOccurrences(of: "<eos>", with: "")
            .replacingOccurrences(of: "<|endoftext|>", with: "")
            .replacingOccurrences(of: "<|assistant|>", with: "")
            .replacingOccurrences(of: "<|user|>", with: "")
            .replacingOccurrences(of: "<|system|>", with: "")
            .replacingOccurrences(of: "<|end|>", with: "")
    }

    private static func synthesizeWithMLX(request: ChatSummaryRequest, modelManager: ModelManager) async -> String? {
        guard let container = await modelManager.getContainerIfReady() else {
            return nil
        }
        guard let context = request.captureContext, !context.isEmpty else {
            return nil
        }

        do {
            let instructions = buildInstructions(context: context)
            let params = GenerateParameters(maxTokens: 512)
            let session = ChatSession(container, instructions: instructions, generateParameters: params)

            var response = ""
            for try await token in session.streamResponse(to: request.rawQuery) {
                response.append(token)
            }

            response = cleanToken(response).trimmingCharacters(in: .whitespacesAndNewlines)
            return response.isEmpty ? nil : response
        } catch {
            logger.warning("MLX synthesis failed: \(error.localizedDescription)")
            return nil
        }
    }
}
