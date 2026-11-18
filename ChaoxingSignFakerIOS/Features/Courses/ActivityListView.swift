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
                    if activity.isSupported {
                        NavigationLink {
                            destination(for: activity)
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

    @ViewBuilder
    private func destination(for activity: ChaoxingActivity) -> some View {
        switch activity.kind {
        case .ordinaryOrPhoto:
            PhotoSignView(model: model, activity: activity)
        case .location:
            LocationSignView(model: model, activity: activity)
        default:
            EmptyView()
        }
    }
}

private struct ActivityRow: View {
    let activity: ChaoxingActivity
    let isSupported: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(activity.isActive ? Color.blue.gradient : Color.secondary.gradient)
                    .frame(width: 56, height: 56)
                Image(systemName: activity.kind.systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white)
            }
            
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
                Text(activity.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !activity.isActive {
                Text("已结束").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

