//
//  OtherUsersView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/25.
//

import SwiftUI

struct OtherUsersView: View {
    @State private var otherUserCount = 3
    
    @State private var showAddUser = false
    @State private var phoneNumber = ""
    @State private var password = ""
    
    @State private var userPhotoCount = 3
    @State private var showEditUserPhoto = false
    
    @State private var showEditUserCollege = false
    @State private var selectedCollege = "天津农学院"
    let colleges = ["天津农学院", "天津农学院图书馆", "天津师范大学"]
    
    var body: some View {
        NavigationStack {
            Group {
                if otherUserCount < 1 {
                    ZStack {
                        ContentUnavailableView(
                            "多账号",
                            systemImage: "person.2",
                            description: Text("暂无其他账号，可通过右上角添加")
                        )
                    }
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        Section(header: Text("其他账号")) {
                            HStack {
                                Image(systemName: "person.circle.fill") // TODO: 这里显示头像
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(.blue.gradient)
                                
                                VStack(alignment: .leading) {
                                    Text("董昊宇") // TODO: 这里显示名字
                                        .font(.headline)
                                    Text("128****1438") // TODO: 这里显示脱敏后的手机号
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    showEditUserCollege = true
                                }) {
                                    Image(systemName: "building.columns")
                                        .foregroundStyle(.blue)
                                }
                                
                                Button(action: {
                                    showEditUserPhoto = true
                                }) {
                                    Image(systemName: "person.fill.viewfinder")
                                        .foregroundStyle(.blue)
                                }
                                
                                Button(action: {
                                    // TODO: 删除用户，删除前要弹窗确认
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            HStack {
                                Image(systemName: "person.circle.fill") // TODO: 这里显示头像
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(.green.gradient)
                                
                                VStack(alignment: .leading) {
                                    Text("张承志") // TODO: 这里显示名字
                                        .font(.headline)
                                    Text("155****2754") // TODO: 这里显示脱敏后的手机号
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    showEditUserCollege = true
                                }) {
                                    Image(systemName: "building.columns")
                                        .foregroundStyle(.blue)
                                }
                                
                                Button(action: {
                                    showEditUserPhoto = true
                                }) {
                                    Image(systemName: "person.fill.viewfinder")
                                        .foregroundStyle(.blue)
                                }
                                
                                Button(action: {
                                    // TODO: 删除用户，删除前要弹窗确认
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            HStack {
                                Image(systemName: "person.circle.fill") // TODO: 这里显示头像
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(.purple.gradient)
                                
                                VStack(alignment: .leading) {
                                    Text("姜钙盐") // TODO: 这里显示名字
                                        .font(.headline)
                                    Text("138****1234") // TODO: 这里显示脱敏后的手机号
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    showEditUserCollege = true
                                }) {
                                    Image(systemName: "building.columns")
                                        .foregroundStyle(.blue)
                                }
                                
                                Button(action: {
                                    showEditUserPhoto = true
                                }) {
                                    Image(systemName: "person.fill.viewfinder")
                                        .foregroundStyle(.blue)
                                }
                                
                                Button(action: {
                                    // TODO: 删除用户，删除前要弹窗确认
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    } // TODO: List可左划删除，删除前要弹窗确认
                }
            }
            .navigationTitle("多账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddUser = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddUser) {
            addUser
        }
        .sheet(isPresented: $showEditUserPhoto) {
            editUserPhoto
        }
        .sheet(isPresented: $showEditUserCollege) {
            editUserCollege
        }
        
    }
    
    private var editUserCollege: some View {
        NavigationStack {
            ZStack {
                VStack {
                    HStack {
                        Text("选择院校机构")
                        
                        Spacer()
                        
                        Picker("课程类型", selection: $selectedCollege) {
                            ForEach(colleges, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding()
                    .background(.white)
                    .cornerRadius(48)
                    .padding(.horizontal)
                    .padding(.top)
                    
                    Spacer()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("为董昊宇管理院校机构") // TODO: 这里标题格式：“为{姓名}管理院校机构”
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showEditUserCollege = false }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
    
    private var editUserPhoto: some View {
        NavigationStack {
            ZStack {
                VStack {
                    if userPhotoCount < 1 {
                        ContentUnavailableView(
                            "人脸照片",
                            systemImage: "person.fill.viewfinder",
                            description: Text("暂无人脸照片，可通过相册或拍照添加")
                        )
                    } else {
                        List {
                            Section(header: Text("人脸照片")) {
                                HStack {
                                    Image("image1")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .leading) {
                                        Text("照片1") // TODO: 这里显示照片次序
                                            .font(.headline)
                                        Text("于2026-11-25 14:28添加") // TODO: 这里显示时间
                                            .foregroundStyle(.secondary)
                                            .font(.subheadline)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        // TODO: 删除照片，删除前要弹窗确认
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        } // TODO: List可左划删除，删除前要弹窗确认
                    }
                    
                    VStack(spacing: 8) {
                        Button(action: {
                            // TODO: 这里实现从相册选择照片
                        }) {
                            ZStack {
                                Capsule()
                                    .frame(height: 48)
                                Text("从相册选择照片")
                                    .foregroundStyle(.white)
                            }
                        }
                        
                        Button(action: {
                            // TODO: 这里实现从相机拍摄照片
                        }) {
                            ZStack {
                                Capsule()
                                    .frame(height: 48)
                                Text("从相机拍摄照片")
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("为董昊宇管理人脸照片") // TODO: 每个其他用户最多可添加5张人脸照片，这里标题格式：“为{姓名}管理人脸照片”
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showEditUserPhoto = false }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
    
    private var addUser: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("手机号或账号", text: $phoneNumber)
                        .textContentType(.username)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("学习通账号")
                }

                Section {
                    Button {
                        // TODO: 验证账号密码有效性后，将此账号密码安全持久化到本地
                    } label: {
                        HStack {
                            Spacer()
                            Text("添加账号")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("添加账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddUser = false }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

#Preview {
    OtherUsersView()
}
