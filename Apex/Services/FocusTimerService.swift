import Foundation
import Observation

@Observable
final class FocusTimerService {
    var isRunning = false
    var currentProjectName = ""
    var currentProjectCategory = ProjectCategory.personal
    var startTime: Date?
    var elapsedSeconds: Int = 0

    private var timer: Timer?

    var elapsedFormatted: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    func start(projectName: String, category: ProjectCategory) {
        currentProjectName = projectName
        currentProjectCategory = category
        startTime = Date()
        elapsedSeconds = 0
        isRunning = true
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.elapsedSeconds += 1
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @discardableResult
    func stop() -> (name: String, category: ProjectCategory, minutes: Int) {
        timer?.invalidate()
        timer = nil
        isRunning = false
        let minutes = max(1, elapsedSeconds / 60)
        let result = (currentProjectName, currentProjectCategory, minutes)
        elapsedSeconds = 0
        return result
    }
}
