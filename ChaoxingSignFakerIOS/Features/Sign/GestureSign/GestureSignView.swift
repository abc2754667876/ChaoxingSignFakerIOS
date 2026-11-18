//
//  GestureSignView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/18.
//

import SwiftUI

struct GestureSignView: View {
    @State private var signed = false
    
    @State private var selection = 0
    
    @State private var isShowingLocations = true
    @State private var detent: PresentationDetent = .fraction(0.45)
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: signed ? "checkmark.circle.fill" : "hand.draw")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(signed ? .green : .blue)
                .contentTransition(.symbolEffect(.replace))

            Text("手势签到")
                .font(.largeTitle)
            Text(signed ? "签到成功" : "在下方绘制手势以签到")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Group {
                if signed {
                    ZStack {
                        Capsule()
                            .fill(.green)
                            .frame(height: 48)
                        Text("已签到")
                            .foregroundStyle(.white)
                    }
                } else {
                    // TODO: 这里写一个九宫格绘制手势组件
                }
            }
            .padding(.top, 72)
        }
        .padding(.horizontal)
        .navigationTitle("拍照签到")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingLocations) {
            // TODO: 若当前手势签到还需要选择位置，则弹出locationsSheet
            locationsSheet
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
    }
    
    private var locationsSheet: some View {
        NavigationStack {
            VStack {
                Picker("状态", selection: $selection) {
                    Text("当前位置").tag(0)
                    Text("已收藏位置").tag(1)
                }
                .pickerStyle(.segmented)
                
                if selection == 0 {
                    VStack(spacing: 12) {
                        Spacer()
                        
                        Image(systemName: "location.north")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .foregroundStyle(.blue)
                        Text("天津市西青区天津师范大学主校区劝学楼")
                            .font(.headline)
                        
                        Button(action: {}) {
                            ZStack {
                                Capsule()
                                    .fill(.blue)
                                    .frame(height: 48)
                                Text("使用当前位置签到")
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.top, 32)
                        
                        Spacer()
                    }
                } else {
                    List {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("天津市西青区天津师范大学主校区劝学楼")
                                    .font(.headline)
                                Text("天津市西青区天津师范大学朝晖路")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button("确认签到") {}
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("天津市西青区天津师范大学主校区博理楼")
                                    .font(.headline)
                                Text("天津市西青区天津师范大学朝晖路")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button("确认签到") {}
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("天津市西青区天津师范大学主校区明理楼")
                                    .font(.headline)
                                Text("天津市西青区天津师范大学朝晖路")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button("确认签到") {}
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(.horizontal)
            .navigationTitle("选择签到位置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    GestureSignView()
}
