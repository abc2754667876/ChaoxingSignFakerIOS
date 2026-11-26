import Foundation

enum ChaoxingParsers {
    static func user(from data: Data, phoneNumber: String) throws -> ChaoxingUser {
        let root = try JSONReader.object(from: data)
        guard let message = root.object("msg"),
              let uid = message.integer("uid"),
              let puid = message.integer("puid"),
              let fid = message.integer("fid"),
              let name = message.string("name"), !name.isEmpty else {
            throw ChaoxingError.invalidResponse("无法解析账号信息")
        }

        var schools: [Int: String] = [fid: message.string("schoolname") ?? "未知学校"]
        message.array("unitConfigInfos")?.compactMap { $0 as? JSONObject }.forEach { item in
            guard let schoolFID = item.integer("fid") else { return }
            let schoolName = item.string("schoolname").flatMap { $0.isEmpty ? nil : $0 } ?? "未知学校"
            if schools[schoolFID] == nil || schools[schoolFID] == "未知学校" {
                schools[schoolFID] = schoolName
            }
        }
        let avatar = message.string("pic")?.replacingOccurrences(of: "http://", with: "https://")
        return ChaoxingUser(
            uid: uid,
            puid: puid,
            defaultFID: fid,
            name: name,
            phoneNumber: phoneNumber,
            avatarURL: avatar.flatMap(URL.init(string:)),
            schools: schools.map(ChaoxingSchool.init(id:name:)).sorted { $0.id < $1.id },
            clientID: message.string("clientId")
        )
    }

    static func courses(from data: Data) throws -> [ChaoxingCourse] {
        let root = try JSONReader.object(from: data)
        guard root.integer("result") != 0, let channels = root.array("channelList") else {
            throw ChaoxingError.sessionExpired
        }
        return channels.compactMap { raw -> ChaoxingCourse? in
            guard let channel = raw as? JSONObject,
                  channel["cataName"] != nil,
                  let content = channel.object("content"),
                  let classID = content.integer("id"),
                  let courseContainer = content.object("course"),
                  let course = courseContainer.array("data")?.first as? JSONObject,
                  let courseID = course.int64("id"),
                  let name = course.string("name") else { return nil }
            return ChaoxingCourse(
                courseName: name,
                teacherName: course.string("teacherfactor"),
                courseID: courseID,
                classID: classID,
                className: name,
                imageURL: course.string("imageurl").flatMap {
                    URL(string: $0.replacingOccurrences(of: "http://", with: "https://"))
                },
                schoolName: course.string("schools")
            )
        }
    }

    static func activities(from data: Data, course: ChaoxingCourse) throws -> [ChaoxingActivity] {
        let root = try JSONReader.object(from: data)
        guard let payload = root.object("data") else {
            throw ChaoxingError.invalidResponse(root.string("errorMsg") ?? "无法解析课程活动")
        }
        guard let activities = payload.array("activeList") else {
            throw ChaoxingError.invalidResponse(root.string("errorMsg") ?? "活动列表缺失")
        }
        let ext = JSONReader.string(from: payload["ext"])
        return activities.compactMap { raw -> ChaoxingActivity? in
            guard let item = raw as? JSONObject,
                  let type = item.integer("type"), [2, 74].contains(type),
                  let id = item.int64("id"),
                  let start = item.int64("startTime") else { return nil }
            return ChaoxingActivity(
                id: id,
                startTime: Date(timeIntervalSince1970: TimeInterval(start) / 1_000),
                endTime: item.int64("endTime").map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) },
                userStatus: item.integer("userStatus") ?? 0,
                otherID: item.string("otherId") ?? "",
                isLook: item.integer("isLook") == 1,
                type: type,
                activeType: item.integer("activeType") ?? 0,
                title: item.string("nameOne") ?? "签到",
                status: item.integer("status") ?? 0,
                endTimeDescription: item.string("nameFour") ?? "",
                course: course,
                ext: ext
            )
        }.sorted { $0.startTime > $1.startTime }
    }
}
