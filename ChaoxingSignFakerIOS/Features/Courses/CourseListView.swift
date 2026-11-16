import SwiftUI

struct CourseListView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoadingCourses && model.courses.isEmpty {
                    ProgressView("正在加载课程…")
                } else if let error = model.courseError, model.courses.isEmpty {
                    ContentUnavailableView {
                        Label("课程加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await model.loadCourses() } }
                    }
                } else if model.courses.isEmpty {
                    ContentUnavailableView("暂无课程", systemImage: "books.vertical")
                } else {
                    List(model.courses) { course in
                        NavigationLink(value: course) {
                            CourseRow(course: course)
                        }
                    }
                    .refreshable { await model.loadCourses() }
                }
            }
            .navigationTitle("我的课程")
            .navigationDestination(for: ChaoxingCourse.self) { course in
                ActivityListView(model: model, course: course)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let user = model.user {
                        Text(user.name).font(.subheadline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("退出", role: .destructive) { model.logout() }
                }
            }
            .task {
                if model.courses.isEmpty { await model.loadCourses() }
            }
        }
    }
}

private struct CourseRow: View {
    let course: ChaoxingCourse

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: course.imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.12)
                        .overlay { Image(systemName: "book.closed") }
                }
            }
            .frame(width: 72, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(course.courseName).font(.headline)
                if let teacher = course.teacherName, !teacher.isEmpty {
                    Text(teacher).font(.caption).foregroundStyle(.secondary)
                }
                Text("班级 ID：\(course.classID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

