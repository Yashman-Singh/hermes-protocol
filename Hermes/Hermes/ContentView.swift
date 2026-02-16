//
//  ContentView.swift
//  Hermes
//
//  Created by Yashman Singh on 2/16/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioService = AudioService.shared
    @StateObject private var fluidAudio = FluidAudio.shared
    
    var body: some View {
        ZStack {
            if audioService.isRecordingState {
                NeonOrbView()
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
    
    var body: some View {
        ZStack {
            // 1. Outer Atmosphere (Glow)
            Circle()
                .fill(Color.orange)
                .frame(width: 45, height: 45)
                .blur(radius: 10)
                .opacity(isAnimating ? 0.6 : 0.3)
            
            // 2. Main Body (Neon Orange)
            Circle()
                .fill(Color(red: 1.0, green: 0.5, blue: 0.0))
                .frame(width: 30, height: 30)
                .shadow(color: .orange, radius: 5)
            
            // 3. Core (Hot White Center)
            Circle()
                .fill(LinearGradient(colors: [.white, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
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
