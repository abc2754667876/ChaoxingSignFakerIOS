//
//  HomeView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/17.
//

import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // 正在进行
                    if !model.ongoingActivities.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("正在进行")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            VStack(spacing: 12) {
                                ForEach(Array(model.ongoingActivities.enumerated()), id: \.element.id) { index, activity in
                                    NavigationLink {
                                        destination(for: activity)
                                    } label: {
                                        OnGoingCheckIn(
                                            image: activity.kind.homeSystemImage,
                                            type: activity.kind.title,
                                            course: activity.course.courseName,
                                            time: endTimeText(for: activity)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if index < model.ongoingActivities.count - 1 {
                                        Divider()
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(
                                Color.white,
                                in: RoundedRectangle(cornerRadius: 20)
                            )
                        }
                        .padding(.horizontal, 16)
                    }

                    // 收藏的课程
                    if !model.favoriteCourses.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("收藏的课程")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal) {
                                HStack(spacing: 16) {
                                    ForEach(model.favoriteCourses) { course in
                                        LoveCourse(course: course)
                                    }
                                }
                            }
                            .contentMargins(
                                .horizontal,
                                16,
                                for: .scrollContent
                            )
                            .scrollIndicators(.hidden)
                        }
                    }

                    // 课程列表
                    VStack(alignment: .leading, spacing: 12) {
                        Text("课程列表")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        VStack(spacing: 12) {
                            if model.isLoadingCourses && model.courses.isEmpty {
                                ProgressView("正在加载课程…")
                                    .frame(maxWidth: .infinity)
                            } else if let error = model.courseError, model.courses.isEmpty {
                                ContentUnavailableView {
                                    Label("课程加载失败", systemImage: "wifi.exclamationmark")
                                } description: {
                                    Text(error)
                                } actions: {
                                    Button("重试") {
                                        Task { await model.refreshHome() }
                                    }
                                }
                            } else if model.courses.isEmpty {
                                ContentUnavailableView("暂无课程", systemImage: "books.vertical")
                            } else {
                                ForEach(Array(displayedCourses.enumerated()), id: \.element.id) { index, course in
                                    CourseItem(
                                        course: course,
                                        isFavorite: model.favoriteCourseClassIDs.contains(course.classID)
                                    ) {
                                        model.toggleFavorite(course)
                                    }

                                    if index < displayedCourses.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable {
                await model.refreshHome()
            }
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ChaoxingCourse.self) { course in
                ActivityListView(model: model, course: course)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "qrcode.viewfinder")
                        // TODO: 扫码签到，暂不实现，此TODO保留
                    }
                }
            }
            .task {
                if model.courses.isEmpty {
                    await model.loadCourses()
                }
                if model.ongoingActivities.isEmpty {
                    await model.loadOngoingActivities()
                }
            }
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
            ActivityListView(model: model, course: activity.course)
        }
    }

    private func endTimeText(for activity: ChaoxingActivity) -> String {
        if let endTime = activity.endTime {
            return "将于\(endTime.formatted(.dateTime.month().day().hour().minute()))结束"
        }
        if !activity.endTimeDescription.isEmpty {
            return activity.endTimeDescription
        }
        return "签到正在进行中"
    }

    private var displayedCourses: [ChaoxingCourse] {
        model.courses.enumerated()
            .sorted { lhs, rhs in
                let isLeftFavorite = model.favoriteCourseClassIDs.contains(lhs.element.classID)
                let isRightFavorite = model.favoriteCourseClassIDs.contains(rhs.element.classID)
                if isLeftFavorite != isRightFavorite {
                    return isLeftFavorite
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

struct CourseItem: View {
    let course: ChaoxingCourse
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack {
            NavigationLink(value: course) {
                HStack {
                    CourseArtwork(url: course.imageURL)
                        .frame(width: 72, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            Text(course.courseName)
                                .font(.headline)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        Text(course.teacherDisplayName)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "取消收藏" : "收藏课程")
        }
    }
}

struct OnGoingCheckIn: View {
    var image: String
    var type: String
    var course: String
    var time: String

    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.blue.gradient)
                    .frame(width: 56, height: 56)
                Image(systemName: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading) {
                Text(type)
                    .font(.headline)
                Text(course)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Text(time)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
    }
}

struct LoveCourse: View {
    let course: ChaoxingCourse

    var body: some View {
        NavigationLink(value: course) {
            VStack(spacing: 0) {
                CourseArtwork(url: course.imageURL)
                    .frame(width: 196, height: 148)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            topTrailingRadius: 20
                        )
                    )

                ZStack {
                    CourseArtwork(url: course.imageURL)
                        .frame(width: 196, height: 116)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(course.courseName)
                                .lineLimit(2)

                            Spacer()

                            Text(course.teacherDisplayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(.regularMaterial)
                    .frame(width: 196, height: 116)
                }
                .frame(width: 196, height: 116)
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20
                    )
                )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CourseArtwork: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.12)
                    .overlay {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipped()
    }
}

private extension ChaoxingCourse {
    var teacherDisplayName: String {
        if let teacherName, !teacherName.isEmpty {
            return teacherName
        }
        if let schoolName, !schoolName.isEmpty {
            return schoolName
        }
        return "教师信息暂无"
    }
}

private extension ChaoxingSignKind {
    var homeSystemImage: String {
        switch self {
        case .ordinaryOrPhoto: "hand.tap"
        case .gesture: "hand.draw"
        case .location: "location"
        case .qrCode: "qrcode"
        case .password: "ellipsis.rectangle"
        case .unknown: "questionmark.circle"
        }
    }
}

#Preview {
    HomeView(model: AppModel())
}
