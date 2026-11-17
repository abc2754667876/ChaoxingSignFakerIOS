//
//  PhotoSignView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/17.
//

import SwiftUI

struct PhotoSignView: View {
    @State private var signed = false
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: signed ? "checkmark.circle.fill" : "camera")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(signed ? .green : .blue)
                .contentTransition(.symbolEffect(.replace))

            Text("拍照签到")
                .font(.largeTitle)
            Text(signed ? "签到成功" : "通过相机或相册选择图片签到")
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
                        Text(signed ? "已签到" : "相机拍摄图片")
                            .foregroundStyle(.white)
                    }
                }
                
                if !signed {
                    Button(action: {
                        withAnimation {
                            signed.toggle()
                        }
                    }) {
                        ZStack {
                            Capsule()
                                .fill(signed ? .green : .blue)
                                .frame(height: 48)
                            Text(signed ? "已签到" : "相册选择图片")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(.top, 72)
        }
        .padding(.horizontal)
        .navigationTitle("拍照签到")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PhotoSignView()
}
