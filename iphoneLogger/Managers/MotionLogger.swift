import Foundation
import CoreMotion
import Combine

class MotionLogger: ObservableObject {
    // CMBatchedSensorManager는 iOS 17.0 이상에서 도입된 초고주파수 배치 모션 로거입니다.
    private var batchedManager: CMBatchedSensorManager?
    
    @Published var isLogging = false
    @Published var currentAccelHz: Int = 0
    @Published var currentGyroHz: Int = 0
    
    // 내부 상태용
    private var accelTickCount = 0
    private var gyroTickCount = 0
    private var hzTimer: Timer?
    
    init() {
        if #available(iOS 17.0, *) {
            if CMBatchedSensorManager.isAccelerometerSupported && CMBatchedSensorManager.isDeviceMotionSupported {
                self.batchedManager = CMBatchedSensorManager()
            } else {
                print("⚠️ 기기가 CMBatchedSensorManager를 지원하지 않습니다 (iPhone 15 Pro 이상 권장).")
            }
        }
    }
    
    func startLogging() {
        guard !isLogging else { return }
        
        if #available(iOS 17.0, *) {
            guard let manager = batchedManager else { return }
            
            isLogging = true
            
            // 1. Hz 측정을 위한 타이머 (UI 렌더링용)
            startHzTimer()
            
            Task {
                do {
                    // 2. 가속도계 스트림 시작 (최대 800Hz)
                    for try await accelBatch in manager.accelerometerUpdates() {
                        if !self.isLogging { break }
                        processAccelBatch(accelBatch)
                    }
                } catch {
                    print("가속도계 스트림 에러: \(error)")
                }
            }
            
            Task {
                do {
                    // 3. 자이로/DeviceMotion 스트림 시작
                    for try await motionBatch in manager.deviceMotionUpdates() {
                        if !self.isLogging { break }
                        processMotionBatch(motionBatch)
                    }
                } catch {
                    print("자이로 스트림 에러: \(error)")
                }
            }
            
        } else {
            print("⚠️ CMBatchedSensorManager는 iOS 17 이상에서만 작동합니다.")
        }
    }
    
    func stopLogging() {
        isLogging = false
        hzTimer?.invalidate()
        hzTimer = nil
        currentAccelHz = 0
        currentGyroHz = 0
    }
    
    // MARK: - Data Processing
    
    private func processAccelBatch(_ batch: [CMAccelerometerData]) {
        let sysTimestamp = Date().timeIntervalSince1970
        // [Key Decision 1 & 2]: 메인 스레드를 피해 800Hz 배열 통째로 BufferQueue (Layer 4) 로 방출.
        // thermalState는 0(Nominal) 으로 임시 하드코딩 (차후 SystemMonitor와 연동)
        BufferQueue.shared.enqueue(accelerometerBatch: batch, sysTimestamp: sysTimestamp, targetHz: 800, thermalState: 0)
        
        DispatchQueue.main.async {
            self.accelTickCount += batch.count
        }
    }
    
    @available(iOS 17.0, *)
    private func processMotionBatch(_ batch: [CMDeviceMotion]) {
        let sysTimestamp = Date().timeIntervalSince1970
        BufferQueue.shared.enqueue(deviceMotionBatch: batch, sysTimestamp: sysTimestamp, targetHz: 200, thermalState: 0)
        
        DispatchQueue.main.async {
            self.gyroTickCount += batch.count
        }
    }
    
    // MARK: - Dashboard UI Updates
    
    private func startHzTimer() {
        hzTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // 1초 단위로 쌓인 틱 카운트를 Hz로 치환하고 UI를 업데이트
            self.currentAccelHz = self.accelTickCount
            self.currentGyroHz = self.gyroTickCount
            
            // 다음 초를 위해 리셋
            self.accelTickCount = 0
            self.gyroTickCount = 0
        }
    }
}
