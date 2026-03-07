import SwiftUI
import Combine

struct DashboardView: View {
    @EnvironmentObject var logController: LogController
    @StateObject private var motionLogger = MotionLogger()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Edge AI Testbed")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                    
                    Text("Phase Selector")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .padding(.top, 40)
                
                // Status Indicators
                HStack(spacing: 30) {
                    VStack {
                        Text("🌡️ Thermal")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(thermalStateString)
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.green)
                    }
                    VStack {
                        Text("🔋 Battery")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("N/A")
                            .font(.subheadline)
                            .bold()
                    }
                }
                .padding(.vertical, 10)
                
                // Stress Test Button (Phase 2)
                Button(action: {
                    // 추후 전체 로거 동시 가동
                }) {
                    Text("🔴 START ALL (Stress Test)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red, lineWidth: 2)
                        )
                }
                .padding(.horizontal)
                
                Divider().background(Color.gray.opacity(0.3))
                
                // Phase 1 Isolating Sensors
                VStack(alignment: .leading, spacing: 16) {
                    Text("Phase 1: Isolating Modules")
                        .font(.title3)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.horizontal)
                    
                    // Motion Sensor Card
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Motion (IMU)")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            if motionLogger.isLogging {
                                Text("Accel: \(motionLogger.currentAccelHz)Hz / Gyro: \(motionLogger.currentGyroHz)Hz 🟢")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            } else {
                                Text("Idle ⚪️")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { motionLogger.isLogging },
                            set: { newValue in
                                if newValue {
                                    BufferQueue.shared.startRecording()
                                    motionLogger.startLogging()
                                } else {
                                    motionLogger.stopLogging()
                                    BufferQueue.shared.stopRecording()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 50)
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
    
    private var thermalStateString: String {
        switch logController.thermalState {
        case .nominal: return "Nominal 🟢"
        case .fair: return "Fair 🟡"
        case .serious: return "Serious 🟠"
        case .critical: return "Critical 🔴"
        @unknown default: return "Unknown"
        }
    }
}

// 추후 확장 예정 (임시)
class LogController: ObservableObject {
    @Published var isLoggingAll: Bool = false
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
}
