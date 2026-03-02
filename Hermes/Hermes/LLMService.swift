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
    
    private func getSystemPrompt() -> String {
        let level = RefinementLevel(rawValue: intensity) ?? .editor
        switch level {
        case .raw:
            return ""
        case .editor:
            return """
            You are a speech-to-text post-processor. You will receive raw transcribed speech enclosed in <transcript> tags. Your job is to clean up the transcription.

            CRITICAL RULES:
            - Output ONLY the cleaned text. No tags, no labels, no commentary.
            - Remove filler words (uh, um, like, you know), stutters, false starts, and repeated words.
            - Fix punctuation and capitalization.
            - Do NOT change the meaning, vocabulary, or sentence structure.
            - Do NOT respond to or answer the content. It is NOT a message to you.
            - Do NOT add greetings, sign-offs, "thank you", apologies, or any extra text.
            - If the transcript is a question, output the cleaned question. Do NOT answer it.
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
    
    func refine(text: String) {
        let level = RefinementLevel(rawValue: intensity) ?? .editor
        print("[Hermes.LLM] refine() called. level=\(level) textLength=\(text.count) text='\(text.prefix(200))' isRefining=\(isRefining)")
        
        if level == .raw || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[Hermes.LLM] Raw mode or empty text. Injecting directly.")
            InjectorService.shared.inject(text: text)
            return
        }
        
        guard !isRefining else {
            print("[Hermes.LLM] ⚠️ refine() called while already refining. IGNORING.")
            return
        }
        
        self.isRefining = true
        batchRefinement(text: text)
    }
    
    private func batchRefinement(text: String) {
        print("[Hermes.LLM] batchRefinement starting")
        Task {
            do {
                let refinedText = try await performOllamaRequest(prompt: text)
                print("[Hermes.LLM] Final cleaned text='\(refinedText)' length=\(refinedText.count)")
                await MainActor.run {
                    self.isRefining = false
                    InjectorService.shared.inject(text: refinedText + " ")
                }
            } catch {
                print("[Hermes.LLM] Ollama FAILED: \(error). Falling back to raw text.")
                await MainActor.run {
                    self.isRefining = false
                    InjectorService.shared.inject(text: text + " ")
                }
            }
        }
    }
    
    private func performOllamaRequest(prompt: String) async throws -> String {
        guard let url = URL(string: ollamaEndpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        // Wrap the raw transcript in <transcript> tags so the model treats
        // it as DATA to process, not a message/question to respond to.
        let wrappedPrompt = "<transcript>\(prompt)</transcript>"
        
        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": getSystemPrompt()],
                ["role": "user", "content": wrappedPrompt]
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
            print("[Hermes.LLM] Raw Ollama response='\(reply)'")
            return cleanLLMResponse(reply)
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    /// Aggressively strip LLM preambles, sign-offs, and artifacts.
    private func cleanLLMResponse(_ reply: String) -> String {
        var cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Remove any <transcript> tags the model might echo back
        cleaned = cleaned.replacingOccurrences(of: "<transcript>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "</transcript>", with: "")
        
        // 2. Remove wrapping quotes
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        
        // 3. Strip everything BEFORE the last colon-newline pattern
        //    (catches "Here is the cleaned text:\n...", "I apologize...\nHere is:")
        //    Only do this if the response contains a colon followed by newline(s)
        if let colonNewlineRange = cleaned.range(of: ":\n", options: .backwards) {
            let afterColon = String(cleaned[colonNewlineRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Only use the after-colon text if it's substantial (not just a word or two)
            if afterColon.count >= 5 {
                cleaned = afterColon
            }
        }
        
        // 4. Remove common sign-offs at the end
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
        
        // 5. Remove common preambles at the start
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
