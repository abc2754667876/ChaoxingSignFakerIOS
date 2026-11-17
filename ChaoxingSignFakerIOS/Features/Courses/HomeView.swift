//
//  HomeView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/17.
//

import SwiftUI

// TODO: 实际实现时，按照项目现有实际结构对视图、逻辑等进行拆分。这里为了方便写参考UI临时写到一起了。

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // 正在进行
                    // TODO: 若当前没有正在进行的签到，则此部分不显示
                    VStack(alignment: .leading, spacing: 12) {
                        Text("正在进行")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        VStack(spacing: 12) {
                            OnGoingCheckIn(image: "location", type: "位置签到", course: "数据挖掘", time: "11-1 14:28")
                            
                            Divider()
                                .padding(.leading, 56)
                            
                            OnGoingCheckIn(image: "qrcode", type: "二维码签到", course: "算法分析与设计", time: "11-2 9:28")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                    }
                    .padding(.horizontal, 16)
                    
                    // 收藏的课程
                    // TODO: 若没有收藏的课程，则此部分不显示
                    VStack(alignment: .leading, spacing: 12) {
                        Text("收藏的课程")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        
                        ScrollView(.horizontal) {
                            HStack(spacing: 16) {
                                LoveCourse(
                                    image: "image1",
                                    name: "数据挖掘",
                                    teacher: "马春梅"
                                )
                                
                                LoveCourse(
                                    image: "image2",
                                    name: "高级算法设计与分析",
                                    teacher: "王淑琴"
                                )
                            }
                        }
                        .contentMargins(
                            .horizontal,
                            16,
                            for: .scrollContent
                        )
                        .scrollIndicators(.hidden)
                    }
                    
                    // 课程列表
                    VStack(alignment: .leading, spacing: 12) {
                        Text("课程列表")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        
                        VStack(spacing: 12) {
                            CourseItem(image: "image1", course: "数据挖掘", teacher: "马春梅", love: true)
                            
                            Divider()
                            
                            CourseItem(image: "image2", course: "高级算法设计与分析", teacher: "王淑琴", love: true)
                            
                            Divider()
                            
                            CourseItem(image: "image3", course: "高级计算机系统结构", teacher: "胡燕翔")
                            
                            Divider()
                            
                            CourseItem(image: "image4", course: "论文写作指导", teacher: "张珑")
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
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "qrcode.viewfinder")
                        // TODO: 扫码签到，暂不实现，此TODO保留
                    }
                }
            }
        }
    }
}

struct CourseItem: View {
    var image: String
    var course: String
    var teacher: String
    var love: Bool? = false
    
    var body: some View {
        HStack {
            Image(image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Text(course)
                        .font(.headline)
                    Button(action: {}) {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(teacher)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            
            Spacer()
            
            Button(action: {}) {// TODO: 点击后进行收藏/取消收藏操作，本地持久化
                if let _love = love {
                    Image(systemName: _love ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                }
            }
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
                Text("将于\(time)结束")
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
    var image: String
    var name: String
    var teacher: String
    
    var body: some View {
        VStack(spacing: 0) {
            Image(image)
                .resizable()
                .scaledToFill()
                .frame(width: 196, height: 148)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        topTrailingRadius: 20
                    )
                )
            
            ZStack {
                Image(image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 196, height: 116)
                HStack {
                    VStack(alignment: .leading) {
                        Text(name)
                        
                        Spacer()
                        
                        Text(teacher)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
}

#Preview {
    HomeView()
}
