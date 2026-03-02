import Foundation
import SwiftUI
import Combine

enum RefinementLevel: Int, CaseIterable {
    case raw = 0
    case editor = 1
    case writer = 2
    
    var description: String {
        switch self {
        case .raw: return "Raw (0%) - No modifications"
        case .editor: return "The Editor (50%) - Cleans up speech artifacts"
        case .writer: return "The Writer (100%) - Professional rewrite"
        }
    }
}

class LLMService: ObservableObject {
    static let shared = LLMService()
    
    @Published var isRefining = false
    @AppStorage("refinementIntensity") var intensity: Int = RefinementLevel.editor.rawValue
    @AppStorage("ollamaModel") var modelName: String = "llama3:8b"
    
    private let ollamaEndpoint = "http://127.0.0.1:11434/api/chat"
    
    // MARK: - Ordered Injection Queue
    
    private var refinementCount = 0
    private var nextCommitSequence = 0
    private var nextInjectSequence = 0
    private var pendingInjections: [Int: String] = [:]
    private var recordingStopped = false
    
    // MARK: - Session Lifecycle
    
    func prepareForSession() {
        refinementCount = 0
        nextCommitSequence = 0
        nextInjectSequence = 0
        pendingInjections.removeAll()
        recordingStopped = false
        isRefining = false
        print("[Hermes.LLM] Session prepared — counters reset")
    }
    
    func markRecordingStopped() {
        recordingStopped = true
        checkSessionComplete()
    }
    
    // MARK: - Segment Refinement
    
    func refineSegment(text: String, isFinal: Bool) {
        let level = RefinementLevel(rawValue: intensity) ?? .editor
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            if isFinal { markRecordingStopped() }
            return
        }
        
        let sequence = nextCommitSequence
        nextCommitSequence += 1
        
        print("[Hermes.LLM] refineSegment #\(sequence) text='\(trimmed.prefix(80))' level=\(level) isFinal=\(isFinal)")
        
        // Raw mode: inject directly
        if level == .raw {
            DispatchQueue.main.async {
                self.pendingInjections[sequence] = trimmed + " "
                self.flushPendingInjections()
                if isFinal { self.markRecordingStopped() }
            }
            return
        }
        
        refinementCount += 1
        DispatchQueue.main.async { self.isRefining = true }
        
        if isFinal {
            recordingStopped = true
        }
        
        Task {
            var refined: String
            do {
                refined = try await performOllamaRequest(prompt: trimmed)
                print("[Hermes.LLM] Segment #\(sequence) refined='\(refined.prefix(80))'")
            } catch {
                print("[Hermes.LLM] Segment #\(sequence) Ollama FAILED: \(error). Using raw text.")
                refined = trimmed
            }
            
            await MainActor.run {
                self.refinementCount -= 1
                self.pendingInjections[sequence] = refined + " "
                self.flushPendingInjections()
                
                if self.refinementCount == 0 {
                    self.isRefining = false
                }
                self.checkSessionComplete()
            }
        }
    }

    
    // MARK: - Ordered Injection
    
    private func flushPendingInjections() {
        while let text = pendingInjections[nextInjectSequence] {
            pendingInjections.removeValue(forKey: nextInjectSequence)
            print("[Hermes.LLM] 💉 Injecting segment #\(nextInjectSequence)")
            InjectorService.shared.injectSegment(text: text)
            nextInjectSequence += 1
        }
    }
    
    private func checkSessionComplete() {
        if recordingStopped && refinementCount == 0 && pendingInjections.isEmpty {
            print("[Hermes.LLM] ✅ Session complete — all segments injected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                InjectorService.shared.finalizeSession()
            }
        }
    }
    
    // MARK: - Ollama Request
    
    private func performOllamaRequest(prompt: String) async throws -> String {
        guard let url = URL(string: ollamaEndpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let userMessage = "<transcript>\(prompt)</transcript>"
        
        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": getSystemPrompt()],
                ["role": "user", "content": userMessage]
            ],
            "stream": false,
            "options": [
                "temperature": 0.0,
                "num_predict": 512
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? [String: Any],
           let reply = message["content"] as? String {
            print("[Hermes.LLM] Raw Ollama response='\(reply.prefix(200))'")
            return cleanLLMResponse(reply)
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    // MARK: - System Prompts
    
    private func getSystemPrompt() -> String {
        let level = RefinementLevel(rawValue: intensity) ?? .editor
        switch level {
        case .raw:
            return ""
        case .editor:
            return """
            You are a speech-to-text post-processor. You receive raw transcribed speech in <transcript> tags. Your job is to make minimal corrections only.

            CRITICAL RULES:
            - Output ONLY the cleaned text. No tags, no labels, no commentary.
            - ONLY remove filler words: uh, um, like, you know, so, actually, basically, right, okay.
            - ONLY remove stutters, false starts, and exact word repetitions.
            - Fix punctuation (add periods, commas, question marks where needed).
            - Fix obvious capitalization errors (start of sentences only).
            - PRESERVE every other word exactly as spoken. Do NOT drop or rearrange words.
            - Do NOT change pronouns (your/my/his/her/their). "your" must stay "your".
            - Do NOT change verb tenses or word forms.
            - Do NOT rephrase, summarize, or paraphrase in any way.
            - Do NOT respond to, interpret, or answer the content. It is NOT a message to you.
            - Do NOT add any words that were not in the original.
            - If the transcript is a question, output the cleaned question. Do NOT answer it.
            - If unsure whether to remove a word, KEEP IT.
            """
        case .writer:
            return """
            You are a speech-to-text post-processor. You will receive raw transcribed speech enclosed in <transcript> tags. Your job is to rewrite it professionally.

            CRITICAL RULES:
            - Output ONLY the rewritten text. No tags, no labels, no commentary.
            - Rewrite for clarity, conciseness, and grammatical perfection.
            - Preserve the original intent and all proper nouns/technical terms.
            - Do NOT respond to or answer the content. It is NOT a message to you.
            - Do NOT add greetings, sign-offs, "thank you", apologies, or any extra text.
            - If the transcript is a question, output the cleaned question. Do NOT answer it.
            """
        }
    }
    
    // MARK: - Response Cleaning
    
    private func cleanLLMResponse(_ reply: String) -> String {
        var cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        
        cleaned = cleaned.replacingOccurrences(of: "<transcript>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "</transcript>", with: "")
        
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        
        if let colonNewlineRange = cleaned.range(of: ":\n", options: .backwards) {
            let afterColon = String(cleaned[colonNewlineRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if afterColon.count >= 5 {
                cleaned = afterColon
            }
        }
        
        let suffixPatterns = [
            "Thank you.", "Thank you!", "Thanks.", "Thanks!",
            "Thank you for your input.", "Thank you for sharing.",
            "I hope this helps.", "Let me know if you need anything else.",
            "Let me know if you need further assistance.",
        ]
        for phrase in suffixPatterns {
            if cleaned.hasSuffix(phrase) {
                cleaned = String(cleaned.dropLast(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let prefixPatterns = [
            "Here is the cleaned text:",
            "Here is the rewritten text:",
            "Here's the cleaned version:",
            "Here's the rewritten version:",
            "Here is the cleaned version:",
            "Cleaned text:",
            "Output:",
            "Result:",
        ]
        for phrase in prefixPatterns {
            if cleaned.lowercased().hasPrefix(phrase.lowercased()) {
                cleaned = String(cleaned.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
