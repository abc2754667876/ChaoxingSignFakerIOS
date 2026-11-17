//
//  LocationSignView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/17.
//

import SwiftUI

struct LocationSignView: View {
    @State private var signed = false
    @State private var showSheet = true
    @State private var detent: PresentationDetent = .fraction(0.45)
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: signed ? "checkmark.circle.fill" : "location")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(signed ? .green : .blue)
                .contentTransition(.symbolEffect(.replace))

            Text("位置签到")
                .font(.largeTitle)
            Text(signed ? "签到成功" : "使用当前位置或选择位置签到")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack {
                Button(action: {
                    withAnimation {
                        signed.toggle()
                    }
                }) {
                    ZStack {
                        Capsule()
                            .fill(signed ? .green : .blue)
                            .frame(height: 48)
                        Text(signed ? "已签到" : "使用当前位置签到")
                            .foregroundStyle(.white)
                    }
                }
                
                if !signed {
                    Button(action: {
                        showSheet = true
                    }) {
                        ZStack {
                            Capsule()
                                .fill(signed ? .green : .blue)
                                .frame(height: 48)
                            Text(signed ? "已签到" : "使用已收藏位置签到")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(.top, 72)
        }
        .padding(.horizontal)
        .navigationTitle("位置签到")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSheet) {
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
            List {
                Section {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("位置1")
                                .font(.headline)
                            Text("天津师范大学劝学楼")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())

                        Spacer()
                        
                        Button("确认签到") {
                            
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("位置2")
                                .font(.headline)
                            Text("天津师范大学博理楼")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())

                        Spacer()
                        
                        Button("确认签到") {
                            
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("位置3")
                                .font(.headline)
                            Text("天津师范大学明理楼")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())

                        Spacer()
                        
                        Button("确认签到") {
                            // TODO: 这里点击后直接使用此位置签到
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
            .listStyle(.plain)
            .navigationTitle("使用收藏位置签到")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    LocationSignView()
}
