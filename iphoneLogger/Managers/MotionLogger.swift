import Foundation
import CoreMotion
import Combine

class MotionLogger: ObservableObject {
    private let manager = CMMotionManager()
    
    @Published var isLogging = false
    @Published var currentAccelHz: Int = 0
    @Published var currentGyroHz: Int = 0
    
    // UI 업데이트용 실시간 카운트
    private var accelTickCount = 0
    private var gyroTickCount = 0
    private var hzTimer: Timer?
    
    // 센서 데이터를 받을 전용 백그라운드 큐
    private let accelQueue = OperationQueue()
    private let gyroQueue = OperationQueue()
    
    // 내부 뱃치 처리용 임시 저장소 및 Lock (메인 스레드 부하 분산)
    private var tempAccelBatch: [CMAccelerometerData] = []
    private var tempGyroBatch: [CMDeviceMotion] = []
    private let accelLock = NSLock()
    private let gyroLock = NSLock()
    
    init() {
        accelQueue.name = "com.iphoneLogger.accelQueue"
        accelQueue.maxConcurrentOperationCount = 1
        accelQueue.qualityOfService = .userInteractive // 최고 우선순위
        
        gyroQueue.name = "com.iphoneLogger.gyroQueue"
        gyroQueue.maxConcurrentOperationCount = 1
        gyroQueue.qualityOfService = .userInteractive
    }
    
    func startLogging() {
        guard !isLogging else { return }
        isLogging = true
        
        startHzTimer()
        
        // 1. 가속도계 스트림 시작 (목표: 800Hz)
        if manager.isAccelerometerAvailable {
            manager.accelerometerUpdateInterval = 1.0 / 800.0
            manager.startAccelerometerUpdates(to: accelQueue) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                self.processAccelData(data)
            }
        } else {
            print("⚠️ 가속도계를 사용할 수 없습니다.")
        }
        
        // 2. 자이로/DeviceMotion 스트림 시작 (목표: 200Hz)
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 200.0
            manager.startDeviceMotionUpdates(to: gyroQueue) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                self.processGyroData(data)
            }
        } else {
            print("⚠️ DeviceMotion(자이로)을 사용할 수 없습니다.")
        }
    }
    
    func stopLogging() {
        isLogging = false
        hzTimer?.invalidate()
        hzTimer = nil
        currentAccelHz = 0
        currentGyroHz = 0
        
        manager.stopAccelerometerUpdates()
        manager.stopDeviceMotionUpdates()
        
        // 남아있는 배치 털어내기
        accelLock.lock()
        tempAccelBatch.removeAll()
        accelLock.unlock()
        
        gyroLock.lock()
        tempGyroBatch.removeAll()
        gyroLock.unlock()
    }
    
    // MARK: - Data Processing (Custom Batching)
    
    private func processAccelData(_ data: CMAccelerometerData) {
        accelLock.lock()
        tempAccelBatch.append(data)
        let batch = tempAccelBatch
        // 800Hz 기준 40개가 모이면 대략 0.05초(50ms) 분량
        let shouldSend = batch.count >= 40
        if shouldSend {
            tempAccelBatch.removeAll(keepingCapacity: true)
        }
        accelLock.unlock()
        
        if shouldSend {
            let sysTimestamp = Date().timeIntervalSince1970
            // [Key Decision 1 & 2]: 메인 스레드를 피해 배열 통째로 BufferQueue 로 방출
            // thermalState는 0(Nominal) 으로 임시 하드코딩
            BufferQueue.shared.enqueue(accelerometerBatch: batch, sysTimestamp: sysTimestamp, targetHz: 800, thermalState: 0)
            
            DispatchQueue.main.async {
                self.accelTickCount += batch.count
            }
        }
    }
    
    private func processGyroData(_ data: CMDeviceMotion) {
        gyroLock.lock()
        tempGyroBatch.append(data)
        let batch = tempGyroBatch
        // 200Hz 기준 20개가 모이면 대략 0.1초 분량
        let shouldSend = batch.count >= 20
        if shouldSend {
            tempGyroBatch.removeAll(keepingCapacity: true)
        }
        gyroLock.unlock()
        
        if shouldSend {
            let sysTimestamp = Date().timeIntervalSince1970
            BufferQueue.shared.enqueue(deviceMotionBatch: batch, sysTimestamp: sysTimestamp, targetHz: 200, thermalState: 0)
            
            DispatchQueue.main.async {
                self.gyroTickCount += batch.count
            }
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
