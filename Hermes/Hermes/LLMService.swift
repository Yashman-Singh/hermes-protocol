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
    @AppStorage("ollamaModel") var modelName: String = "llama3:8b" // Default model
    
    private let ollamaEndpoint = "http://127.0.0.1:11434/api/generate"
    
    private func getSystemPrompt() -> String {
        let level = RefinementLevel(rawValue: intensity) ?? .editor
        switch level {
        case .raw:
            return "" // Raw doesn't use the LLM
        case .editor:
            return """
            You are a strict text conversion engine. Your ONLY output must be the cleaned version of the input.
            RULES:
            1. Remove filler words (uh, um, like), stutters, and false starts.
            2. Add necessary punctuation and capitalization.
            3. Do NOT change vocabulary, tone, or sentence structure.
            4. Preserve ALL proper nouns and technical terms exactly as spoken.
            5. ABSOLUTELY NO PREAMBLE, NO EXPLANATION, NO QUOTES. Output NOTHING but the text.
            """
        case .writer:
            return """
            You are a strict text conversion engine. Your ONLY output must be the rewritten version of the input.
            RULES:
            1. Rewrite the text to be clear, concise, and grammatically perfect.
            2. Ensure smooth flow and professional tone.
            3. Preserve the original intent and specific names/technical terms.
            4. ABSOLUTELY NO PREAMBLE, NO EXPLANATION, NO QUOTES. Output NOTHING but the text.
            """
        }
    }
    
    func refine(text: String) {
        let level = RefinementLevel(rawValue: intensity) ?? .editor
        
        // Short-circuit if raw
        if level == .raw || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            InjectorService.shared.inject(text: text)
            return
        }
        
        // Set refining state immediately (synchronously) so the overlay
        // stays visible during the transition from recording → refining.
        // This must happen BEFORE isRecordingState is set to false to
        // prevent a (false, false) gap in the CombineLatest sink.
        self.isRefining = true
        
        // Determine whether to stream based on injection method (Clipboard vs Accessibility)
        // Assume non-streaming (batch) by default for safety, but check InjectorService if we can stream
        let canStream = InjectorService.shared.canUseAccessibilityForCurrentApp()
        
        if canStream {
            streamRefinement(text: text)
        } else {
            batchRefinement(text: text)
        }
    }
    
    private func batchRefinement(text: String) {
        Task {
            do {
                let refinedText = try await performOllamaRequest(prompt: text, stream: false)
                await MainActor.run {
                    self.isRefining = false
                    InjectorService.shared.inject(text: refinedText + " ")
                }
            } catch {
                print("LLM Refinement failed: \(error). Falling back to raw text.")
                await MainActor.run {
                    self.isRefining = false
                    InjectorService.shared.inject(text: text + " ") // Fallback
                }
            }
        }
    }
    
    private func streamRefinement(text: String) {
        // Advanced streaming implementation goes here
        // For iteration 1, we will still do batch but pretend it's streaming, 
        // to ensure stability. Real streaming requires chunking the response and modifying InjectorService.
        // Let's stick to batch for now to ensure clipboard history isn't destroyed.
        batchRefinement(text: text)
    }
    
    private func performOllamaRequest(prompt: String, stream: Bool) async throws -> String {
        guard let url = URL(string: ollamaEndpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = getSystemPrompt()
        let fullPrompt = "\(systemPrompt)\n\nOriginal Text: \(prompt)"
        
        let body: [String: Any] = [
            "model": modelName,
            "prompt": fullPrompt,
            "stream": stream,
            "options": [
                "temperature": 0.0, // Highly deterministic to prevent hallucinations of proper nouns
                "num_predict": 512
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Ollama returns a JSON response: {"response": "..."}
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reply = json["response"] as? String {
            // Trim newlines, spaces, and any accidental quotes the model might have wrapped the text in
            var cleanedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedReply.hasPrefix("\"") && cleanedReply.hasSuffix("\"") && cleanedReply.count >= 2 {
                cleanedReply = String(cleanedReply.dropFirst().dropLast())
            }
            return cleanedReply.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
}
