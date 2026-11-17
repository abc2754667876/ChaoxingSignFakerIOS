import SwiftUI

struct ActivityListView: View {
    let model: AppModel
    let course: ChaoxingCourse

    @State private var activities: [ChaoxingActivity] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && activities.isEmpty {
                ProgressView("正在加载活动…")
            } else if let errorMessage, activities.isEmpty {
                ContentUnavailableView {
                    Label("活动加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else if activities.isEmpty {
                ContentUnavailableView("暂无签到活动", systemImage: "tray")
            } else {
                List(activities) { activity in
                    if activity.isOrdinaryCandidate {
                        NavigationLink {
                            PhotoSignView(model: model, activity: activity)
                        } label: {
                            ActivityRow(activity: activity, isSupported: true)
                        }
                    } else {
                        ActivityRow(activity: activity, isSupported: false)
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(course.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .task { if activities.isEmpty { await load() } }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            activities = try await model.loadActivities(for: course)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ActivityRow: View {
    let activity: ChaoxingActivity
    let isSupported: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.kind.systemImage)
                .frame(width: 28)
                .foregroundStyle(activity.isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.title).font(.headline)
                    if !isSupported {
                        Text("未接入")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                }
                Text(activity.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(activity.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !activity.isActive {
                Text("已结束").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

