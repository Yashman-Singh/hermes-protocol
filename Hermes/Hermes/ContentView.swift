//
//  ContentView.swift
//  Hermes
//
//  Created by Yashman Singh on 2/16/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioService = AudioService.shared
    @StateObject private var llmService = LLMService.shared
    
    var body: some View {
        ZStack {
            if audioService.isRecordingState {
                NeonOrbView(isRefining: false)
            } else if llmService.isRefining {
                NeonOrbView(isRefining: true)
            } else {
                // Idle / Loading
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 100, height: 100) // Match window size to prevent clipping
    }
}

struct NeonOrbView: View {
    @State private var isAnimating = false
    var isRefining: Bool = false
    
    var body: some View {
        ZStack {
            // 1. Outer Atmosphere (Glow)
            Circle()
                .fill(isRefining ? Color.purple : Color.orange)
                .frame(width: 45, height: 45)
                .blur(radius: 10)
                .opacity(isAnimating ? 0.6 : 0.3)
            
            // 2. Main Body (Neon Solid)
            Circle()
                .fill(isRefining ? Color(red: 0.5, green: 0.0, blue: 1.0) : Color(red: 1.0, green: 0.5, blue: 0.0))
                .frame(width: 30, height: 30)
                .shadow(color: isRefining ? .purple : .orange, radius: 5)
            
            // 3. Core (Hot White Center)
            Circle()
                .fill(LinearGradient(colors: [.white, isRefining ? .purple : .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 12, height: 12)
                .opacity(0.9)
        }
        .scaleEffect(isAnimating ? 1.1 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    ContentView()
}
