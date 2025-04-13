import SwiftUI

// Wake Word Popup View
struct WakeWordPopupView: View {
    @Binding var isShowing: Bool
    let message: String
    let sessionId: String
    var onContinue: () -> Void
    
    @State private var glowIntensity: CGFloat = 0.4
    @State private var pulseAnimation: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with icon
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
                    .opacity(pulseAnimation ? 1.0 : 0.7)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .onAppear {
                        withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulseAnimation = true
                        }
                    }
                
                Text("Wake Word Detected")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)
            }
            
            // Message with voice visualization
            ZStack {
                // Background with animation
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.1, green: 0.1, blue: 0.3).opacity(0.7),
                                Color.black.opacity(0.6)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.blue.opacity(0.7),
                                        Color.purple.opacity(0.5)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(
                        color: Color.blue.opacity(glowIntensity),
                        radius: 8,
                        x: 0,
                        y: 0
                    )
                
                VStack(spacing: 12) {
                    // Voice visualization
                    HStack(spacing: 4) {
                        ForEach(0..<5) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: 4, height: 15 + CGFloat(index * 5))
                                .opacity(0.7)
                                .animation(
                                    Animation
                                        .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.1),
                                    value: pulseAnimation
                                )
                        }
                    }
                    .padding(.top, 8)
                    
                    // Message text
                    Text(message)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            
            // Session info
            VStack(alignment: .center, spacing: 4) {
                Text("Session ID:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text(sessionId)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.vertical, 8)
            
            // Buttons
            VStack(spacing: 12) {
                // Continue button
                Button(action: {
                    withAnimation {
                        isShowing = false
                        onContinue()
                    }
                }) {
                    Text("Continue to Session")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(color: Color.blue.opacity(0.5), radius: 5)
                }
                
                // Dismiss button
                Button(action: {
                    withAnimation {
                        isShowing = false
                    }
                }) {
                    Text("Dismiss")
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .padding(24)
        .background(
            // Dark glass effect background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.2).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(0.7),
                                    Color.purple.opacity(0.5)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.5), radius: 15)
        .frame(maxWidth: UIScreen.main.bounds.width - 60)
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}
