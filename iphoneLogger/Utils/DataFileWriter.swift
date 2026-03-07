import Foundation

class DataFileWriter {
    private let fileName: String
    private let queue: DispatchQueue
    private var fileHandle: FileHandle?
    
    init(sensorName: String, header: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        self.fileName = "\(sensorName)_\(formatter.string(from: Date())).csv"
        
        // 시리얼 큐(Serial Queue)를 생성하여 여러 스레드에서 파일 쓰기 요청이 와도 Lock 없이 순서대로 파일 I/O 수행
        self.queue = DispatchQueue(label: "com.iphoneLogger.writer.\(sensorName)", qos: .background)
        
        setupFile(header: header)
    }
    
    private func setupFile(header: String) {
        guard let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = docURL.appendingPathComponent(fileName)
        
        do {
            let headerLine = header + "\n"
            try headerLine.write(to: fileURL, atomically: true, encoding: .utf8)
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
            self.fileHandle?.seekToEndOfFile()
            print("📄 [\(fileName)] 파일 생성 완료")
        } catch {
            print("🔴 파일 생성 에러: \(error)")
        }
    }
    
    func write(lines: [String]) {
        queue.async { [weak self] in
            guard let handle = self?.fileHandle else { return }
            let csvStr = lines.joined(separator: "\n") + "\n"
            if let data = csvStr.data(using: .utf8) {
                do {
                    if #available(iOS 13.4, *) {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                    } else {
                        handle.seekToEndOfFile()
                        handle.write(data)
                    }
                } catch {
                    print("🔴 파일 쓰기 에러: \(error)")
                }
            }
        }
    }
    
    func close() {
        queue.async { [weak self] in
            do {
                try self?.fileHandle?.close()
                self?.fileHandle = nil
            } catch {
                print("🔴 파일 종료 에러: \(error)")
            }
        }
    }
}
