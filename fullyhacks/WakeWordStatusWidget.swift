//
//  WakeWordStatusWidget.swift
//  fullyhacks
//
//  Created by Yang Gao on 4/13/25.
//



import SwiftUI

struct WakeWordStatusWidget: View {
    @ObservedObject var audioService: AudioService
    @State private var pulseAnimation = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Pulsing indicator
            Circle()
                .fill(audioService.wakeWordActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
                .scaleEffect(audioService.wakeWordActive && pulseAnimation ? 1.2 : 1.0)
                .opacity(audioService.wakeWordActive && pulseAnimation ? 0.7 : 1.0)
                .animation(
                    audioService.wakeWordActive ? 
                        Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true) : 
                        .default, 
                    value: pulseAnimation
                )
                .onAppear {
                    if audioService.wakeWordActive {
                        pulseAnimation = true
                    }
                }
                .onChange(of: audioService.wakeWordActive) { active in
                    pulseAnimation = active
                }
            
            // Status text
            Text("Wake Word: \(audioService.wakeWordActive ? "Listening" : "Off")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(audioService.wakeWordActive ? .green : .gray)
            
            // Toggle button
            Button(action: {
                if audioService.wakeWordActive {
                    audioService.deactivateWakeWordDetection()
                } else {
                    audioService.activateWakeWordDetection()
                }
            }) {
                Image(systemName: audioService.wakeWordActive ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 12))
                    .foregroundColor(audioService.wakeWordActive ? .green : .gray)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        audioService.wakeWordActive ? Color.green.opacity(0.5) : Color.gray.opacity(0.3),
                                        lineWidth: 1
                                    )
                            )
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.3),
                            Color.purple.opacity(0.2)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            // Check status when widget appears
            audioService.checkWakeWordStatus()
        }
    }
}
