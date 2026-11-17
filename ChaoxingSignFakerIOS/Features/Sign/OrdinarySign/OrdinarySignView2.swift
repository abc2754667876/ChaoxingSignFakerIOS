//
//  OrdinarySignView2.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/17.
//

import SwiftUI

struct OrdinarySignView2: View {
    @State private var signed = false
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: signed ? "checkmark.circle.fill" : "hand.tap")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(signed ? .green : .blue)
                .contentTransition(.symbolEffect(.replace))
            
            Text("普通签到")
                .font(.largeTitle)
            Text(signed ? "已于11-1 14:20签到" : "将于11-1 14:23结束")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: {
                if !signed {
                    withAnimation {
                        signed.toggle()
                    }
                }
            }) {
                ZStack {
                    Capsule()
                        .fill(signed ? .green : .blue)
                        .frame(height: 48)
                    Text(signed ? "已签到" : "确认签到")
                        .foregroundStyle(.white)
                    // TODO: 签到处理时这里显示ProgressView
                }
            }
            .padding(.top, 72)
        }
        .padding(.horizontal)
        .navigationTitle("普通签到")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    OrdinarySignView2()
}
