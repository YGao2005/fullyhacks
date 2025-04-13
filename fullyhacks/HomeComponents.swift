import SwiftUI
import Combine

struct MainNeonButton: View {
    var title: String
    var action: () -> Void
    
    @State private var isPressed = false
    @State private var isHovered = false
    @State private var glowIntensity: CGFloat = 0.6
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
            
            action()
        }) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(
                    .white
//                    LinearGradient(
//                        gradient: Gradient(colors: [.white, Color.blue.opacity(0.7), .white]),
//                        startPoint: .leading,
//                        endPoint: .trailing
//                    )
                )
                .padding(.vertical, 16)
                .padding(.horizontal, 70)
                .background(
                    ZStack {
                        // Base fill
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.7),
                                        Color(red: 0.1, green: 0.1, blue: 0.3).opacity(0.8),
                                        Color.black.opacity(0.7)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Outer glow
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.white, .blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .blur(radius: isHovered ? 3 : 1)
                            .shadow(
                                color: Color.blue.opacity(glowIntensity),
                                radius: isHovered ? 12 : 8,
                                x: 0,
                                y: 0
                            )
                        
                        // Inner subtle highlights
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1),
                                        Color.white.opacity(0.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                            .padding(1)
                    }
                )
        }
        .scaleEffect(isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
        .offset(y: isPressed ? 2 : 0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onAppear {
            // Create pulsing glow effect
            withAnimation(Animation.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowIntensity = 0.85
            }
        }
    }
}

struct SecondaryNeonButton: View {
    var title: String
    var action: () -> Void
    
    @State private var isPressed = false
    @State private var isHovered = false
    @State private var glowIntensity: CGFloat = 0.5
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
            
            action()
        }) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [.white.opacity(0.95), .white.opacity(0.7)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.vertical, 14)
                .padding(.horizontal, 70)
                .background(
                    ZStack {
                        // Base fill
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.9),
                                        Color(red: 0.1, green: 0.1, blue: 0.15).opacity(0.9)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Outer glow - more subtle for secondary button
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.white.opacity(0.8), .purple.opacity(0.5)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                            .blur(radius: isHovered ? 2 : 1)
                            .shadow(
                                color: Color.purple.opacity(glowIntensity),
                                radius: isHovered ? 8 : 6,
                                x: 0,
                                y: 0
                            )
                    }
                )
        }
        .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.01 : 1.0))
        .offset(y: isPressed ? 1 : 0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
        .onAppear {
            // Create pulsing glow effect
            withAnimation(Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glowIntensity = 0.7
            }
        }
    }
}

struct HarmonAITitleView: View {
    @State private var glowIntensity: CGFloat = 0.5
    
    var body: some View {
        Text("HarmonAI")
            .font(.system(size: 52, weight: .bold, design: .rounded))
            .foregroundStyle(
                .white
            )
            .shadow(color: .white, radius: 1, x: 0, y: 0)
            .shadow(color: Color.blue.opacity(glowIntensity * 0.7), radius: 8, x: 0, y: 0)
            .shadow(color: Color.purple.opacity(glowIntensity * 0.5), radius: 12, x: 0, y: 0)
            .shadow(color: Color.purple.opacity(glowIntensity * 0.3), radius: 20, x: 0, y: 0)
    
            .padding(.top, 90)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    glowIntensity = 0.8
                }
            }
    }
}


struct HarmonAISubtitleView: View {
    @State private var glowIntensity: CGFloat = 0.4
    
    var body: some View {
        Text("Mediator of the Digital World")
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    gradient: Gradient(colors: [.white.opacity(0.9), .white.opacity(0.6)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: Color.blue.opacity(glowIntensity * 0.7), radius: 10, x: 0, y: 0)
            .tracking(1) // Add letter spacing
            .padding(.top, -25)
            .opacity(0.7)
            .onAppear {
                // Create subtle pulsing effect for the subtitle
                withAnimation(Animation.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    glowIntensity = 0.6
                }
            }
    }
}

struct RecordingButton: View {
    @Binding var isRecording: Bool
    var action: () -> Void
    
    @State private var glowIntensity: CGFloat = 0.6
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Base circle
                Circle()
                    .fill(isRecording ? Color.red.opacity(0.8) : Color.blue.opacity(0.5))
                    .frame(width: 60, height: 60)
                
                // Outer glow
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                isRecording ? .red : .blue,
                                isRecording ? .red.opacity(0.5) : .blue.opacity(0.5)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                    .shadow(
                        color: (isRecording ? Color.red : Color.blue).opacity(glowIntensity),
                        radius: 10,
                        x: 0,
                        y: 0
                    )
                    .frame(width: 62, height: 62)
                
                // Inner circle for recording state
                Circle()
                    .fill(.white.opacity(isRecording ? 0.3 : 0.7))
                    .frame(width: isRecording ? 20 : 32, height: isRecording ? 20 : 32)
            }
            .scaleEffect(scale)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Create pulsing effect
            withAnimation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.9
            }
            
            // Create subtle scale animation if recording
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                if isRecording {
                    scale = 1.1
                }
            }
        }
        // Remove the problematic onChange and use onReceive instead
        .onReceive(Just(isRecording)) { newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                scale = newValue ? 1.1 : 1.0
            }
        }
    }
}
// Assuming GalaxyEffectView is already implemented in your code
// If not, you would need to implement it

// Preview
struct HarmonAIHomeView_Previews: PreviewProvider {
    static var previews: some View {
        HarmonAIHomeView()
            .preferredColorScheme(.dark) // Force dark mode
    }
}
