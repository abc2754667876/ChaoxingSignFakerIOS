//
//  LocationView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/17.
//

import SwiftUI
import MapKit

struct LocationView: View {
    @State private var showSheet = true
    @State private var searchText = ""
    @State private var detent: PresentationDetent = .fraction(0.45)
    
    var body: some View {
        NavigationStack {
            // TODO: 地图视图默认显示用户当前所在的位置
            // TODO: 地图中应在用户收藏的位置上以合适的方式显示图针图标
            // TODO: 用户在地图中点击新位置时，应当弹窗提示是否把当前位置收藏，收藏位置应在本地持久化。
            Map()
                .ignoresSafeArea()
                .sheet(isPresented: $showSheet) {
                    sheetContent
                        .presentationDetents(
                            [.fraction(0.45), .large],
                            selection: $detent
                        )
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(36)
                        .presentationBackgroundInteraction(
                            .enabled(upThrough: .fraction(0.45))
                        )
                }
                .navigationTitle("位置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {}) {
                            Image(systemName: "list.bullet")
                        } // TODO: 点击后弹出/隐藏sheet
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {}) {
                            Image(systemName: "map")
                        } // TODO: 点击后更改地图试图：平面/卫星等等
                    }
                }
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 20) {
            Text("收藏的位置")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 12) {
                    // TODO: 每一项点击后，可以在地图上跳转到地址对应的位置视图
                    
                    LocationItem(name: "位置1", address: "天津市西青区天津师范大学劝学楼", latitude: 34.57, longitude: 107.58)
                    
                    Divider()
                    
                    LocationItem(name: "博理楼", address: "天津市西青区天津师范大学博理楼", latitude: 34.56, longitude: 107.586)
                    
                    Divider()
                    
                    LocationItem(name: "实验室", address: "天津市西青区天津师范大学明理楼C", latitude: 34.56, longitude: 107.53)
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 28)
    }
}

struct LocationItem: View {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                    .font(.headline)
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: {}) { // TODO: 点击后弹窗可更改该条位置的name
                    Image(systemName: "pencil.line")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Button(action: {}) { // TODO: 点击后可删除该条位置，需要弹窗确认
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    LocationView()
}
