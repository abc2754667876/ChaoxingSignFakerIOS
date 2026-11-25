//
//  ProfileView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/25.
//

import SwiftUI

struct ProfileView: View {
    // @Bindable var model: AppModel
    
    @State private var selectedCollege = "天津农学院"
    let colleges = ["天津农学院", "天津师范大学"]

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("当前账号")) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .foregroundStyle(.blue.gradient)
                        
                        VStack(alignment: .leading) {
                            Text("董昊宇")
                                .font(.headline)
                            Text("155****2754")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            // TODO: 这里接入退出登录逻辑
                        }) {
                            Image(systemName: "rectangle.portrait.and.arrow.forward")
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                Section(header: Text("个人信息")) {
                    HStack {
                        Image(systemName: "building.columns")
                            .foregroundStyle(.blue)
                        Text("院校机构")
                        
                        Spacer()
                        
                        Picker("", selection: $selectedCollege) {
                            ForEach(colleges, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    HStack { // TODO: 这里需要可点击，逻辑同“多账号”页面的弹出人脸照片管理sheet，
                        Image(systemName: "person.fill.viewfinder")
                            .foregroundStyle(.blue)
                        Text("管理人脸照片")
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section(header: Text("项目仓库与赞助")) {
                    HStack { // TODO: 这里需要可点击，打开网址“https://github.com/aquamarine5/ChaoxingSignFaker”，
                        Image(systemName: "shippingbox")
                            .foregroundStyle(.blue)
                        Text("aquamarine5/ChaoxingSignFaker")
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack { // TODO: 这里需要可点击，打开网址“https://github.com/abc2754667876/ChaoxingSignFakerIOS”，
                        Image(systemName: "shippingbox")
                            .foregroundStyle(.blue)
                        Text("abc2754667876/ChaoxingSignFakerIOS")
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text("*本项目在aquamarine5/ChaoxingSignFaker基础上进行iOS移植开发，请支持原作者\n**本项目仅作为交流学习使用，通过本项目加深前端设计、接口调用、数据库使用、网络通信安全等方面知识的理解。请勿将此项目用作商业用途和任何不正当违规违法行为。任何人或组织使用项目或项目中的代码进行的任何不正当违规和违法行为与作者无关，作者不承担任何因使用本应用而导致的法律或其他任何责任。")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ProfileView()
}
