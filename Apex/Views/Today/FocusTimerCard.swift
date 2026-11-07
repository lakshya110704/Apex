import SwiftUI
import SwiftData

struct FocusTimerCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FocusSession.startTime, order: .reverse) private var sessions: [FocusSession]
    @Query private var projects: [Project]

    var focusTimer: FocusTimerService

    @State private var selectedProject: Project?
    @State private var showProjectPicker = false

    private var todaySessions: [FocusSession] {
        sessions.filter { $0.date.isToday }
    }
    private var todayTotalMinutes: Int {
        todaySessions.reduce(0) { $0 + $1.durationMinutes }
    }
    private var activeProjects: [Project] {
        projects.filter { $0.isActive }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Focus", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.accentCyan)
                Spacer()
                if todayTotalMinutes > 0 {
                    Text("\(todayTotalMinutes)m today")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.textSecondary)
                }
            }
            .padding(16)

            if focusTimer.isRunning {
                runningView
            } else {
                idleView
            }

            // Today's sessions
            if !todaySessions.isEmpty {
                Divider().background(ApexColor.cardBg2).padding(.horizontal, 16)
                sessionsList
            }
        }
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Running

    private var runningView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(focusTimer.elapsedFormatted)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(ApexColor.accentCyan)
                Text(focusTimer.currentProjectName.isEmpty ? "Focus session" : focusTimer.currentProjectName)
                    .font(.subheadline)
                    .foregroundStyle(ApexColor.textSecondary)
            }
            Spacer()
            Button { stopSession() } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(ApexColor.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(ApexColor.danger)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 10) {
            if activeProjects.isEmpty {
                Text("Add projects in Morning Check-in to start focus sessions")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeProjects) { project in
                            projectChip(project)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func projectChip(_ project: Project) -> some View {
        let isSelected = selectedProject?.id == project.id
        let color = colorForCategory(project.category)
        return Button {
            if isSelected {
                startSession(project: project)
            } else {
                selectedProject = project
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: project.category.systemImage)
                    .font(.caption)
                Text(project.name)
                    .font(.caption.bold())
                if isSelected {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                }
            }
            .foregroundStyle(isSelected ? ApexColor.background : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(isSelected ? 0 : 0.3), lineWidth: 1))
        }
    }

    // MARK: - Sessions List

    private var sessionsList: some View {
        VStack(spacing: 0) {
            ForEach(todaySessions.prefix(3)) { session in
                HStack(spacing: 10) {
                    Circle()
                        .fill(colorForCategoryString(session.projectCategory))
                        .frame(width: 6, height: 6)
                    Text(session.projectName)
                        .font(.caption)
                        .foregroundStyle(ApexColor.textPrimary)
                    Spacer()
                    Text("\(session.durationMinutes)m")
                        .font(.caption.bold())
                        .foregroundStyle(ApexColor.textSecondary)
                    Text(session.startTime.shortTime)
                        .font(.caption2)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func startSession(project: Project) {
        focusTimer.start(projectName: project.name, category: project.category)
        selectedProject = nil
    }

    private func stopSession() {
        let result = focusTimer.stop()
        let session = FocusSession(
            projectName: result.name,
            projectCategory: result.category,
            durationMinutes: result.minutes
        )
        session.endTime = Date()
        context.insert(session)
    }

    private func colorForCategory(_ category: ProjectCategory) -> Color {
        switch category {
        case .startup:  return ApexColor.accent
        case .study:    return ApexColor.accentCyan
        case .fitness:  return ApexColor.success
        case .personal: return ApexColor.warning
        case .work:     return Color.green
        case .creative: return ApexColor.danger
        }
    }

    private func colorForCategoryString(_ raw: String) -> Color {
        colorForCategory(ProjectCategory(rawValue: raw) ?? .work)
    }
}
