import Foundation
import CoreMotion

class BufferQueue: ObservableObject {
    static let shared = BufferQueue()
    
    // 독립적인 DataFileWriter 스레드 채택 (Multi-CSV)
    private var accelWriter: DataFileWriter?
    private var gyroWriter: DataFileWriter?
    
    // 이 큐들은 오직 파일 쓰기 병목이 발생할 때 메모리에서 완충(Buffer) 역할을 하는 임시 큐입니다.
    private var accelBuffer: [String] = []
    private var gyroBuffer: [String] = []
    
    private let writeInterval: TimeInterval = 0.5 // 0.5초마다 쓰기 배치(Batch)
    private var timer: Timer?
    
    // PRD 공통 메타 스키마 상수
    let schemaHeader = "hw_timestamp,sys_timestamp,target_c_hz,thermal_state,"
    
    public func startRecording(targetHz: Int = 800) {
        // [1] CSV 파일 2개 독립 생성 (Lock 분산)
        accelWriter = DataFileWriter(sensorName: "motion_accel", header: schemaHeader + "x,y,z")
        gyroWriter = DataFileWriter(sensorName: "motion_gyro", header: schemaHeader + "pitch,roll,yaw")
        
        accelBuffer.removeAll()
        gyroBuffer.removeAll()
        
        // [2] 백그라운드 스레드에서 주기적으로 Buffer 플러시(Flush) 타이머 작동
        timer = Timer.scheduledTimer(withTimeInterval: writeInterval, repeats: true) { [weak self] _ in
            self?.flushBuffers()
        }
    }
    
    public func flushBuffers() {
        guard !accelBuffer.isEmpty || !gyroBuffer.isEmpty else { return }
        
        if !accelBuffer.isEmpty {
            let chunk = accelBuffer
            accelBuffer.removeAll() // 비우기
            accelWriter?.write(lines: chunk)
        }
        
        if !gyroBuffer.isEmpty {
            let chunk = gyroBuffer
            gyroBuffer.removeAll()
            gyroWriter?.write(lines: chunk)
        }
    }
    
    public func stopRecording() {
        timer?.invalidate()
        timer = nil
        flushBuffers() // 남은 데이터 모두 방출
        
        accelWriter?.close()
        gyroWriter?.close()
        print("🛑 파일 스트림 모두 닫힘.")
    }
    
    // MARK: - Enqueue Streams (Layer 2 -> Layer 4)
    
    // (Batched Data) 초당 800번 들어오는 가속도 데이터를 이 함수가 수신
    public func enqueue(accelerometerBatch: [CMAccelerometerData], sysTimestamp: Double, targetHz: Int, thermalState: Int) {
        
        let newLines = accelerometerBatch.map { data -> String in
            // Schema: hw_timestamp, sys_timestamp, target_c_hz, thermal_state, x, y, z
            return "\(data.timestamp),\(sysTimestamp),\(targetHz),\(thermalState),\(data.acceleration.x),\(data.acceleration.y),\(data.acceleration.z)"
        }
        accelBuffer.append(contentsOf: newLines)
        
        // 만약 버퍼가 너무 커지면(예: 드롭아웃 현상 관측을 위해) 강제로 Flush
        if accelBuffer.count > 2000 {
            flushBuffers()
        }
    }
    
    @available(iOS 17.0, *)
    public func enqueue(deviceMotionBatch: [CMDeviceMotion], sysTimestamp: Double, targetHz: Int, thermalState: Int) {
        let newLines = deviceMotionBatch.map { data -> String in
            return "\(data.timestamp),\(sysTimestamp),\(targetHz),\(thermalState),\(data.attitude.pitch),\(data.attitude.roll),\(data.attitude.yaw)"
        }
        gyroBuffer.append(contentsOf: newLines)
    }
}
