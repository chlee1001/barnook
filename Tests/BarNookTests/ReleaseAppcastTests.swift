import CryptoKit
import Foundation
import Testing

struct ReleaseAppcastTests {
    @Test func validatesThePublishedArchive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let version = "0.1.0"
        let zip = directory.appendingPathComponent("BarNook-\(version).zip")
        let appcast = directory.appendingPathComponent("appcast.xml")
        let plist = directory.appendingPathComponent("Info.plist")
        let archive = Data("signed archive".utf8)
        let key = Curve25519.Signing.PrivateKey()
        let signature = try key.signature(for: archive).base64EncodedString()
        let info: [String: Any] = [
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "123",
            "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString(),
        ]
        try archive.write(to: zip)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)

        func feed(build: String = "123", length: Int? = nil, url: String? = nil,
                  namespace: String = "", enclosureVersion: String = "",
                  extraVersion: String = "", extraItem: String = "") -> String {
            let download = url ?? "https://github.com/chlee1001/barnook/releases/download/v\(version)/BarNook-\(version).zip"
            return """
            <?xml version="1.0"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" \(namespace) version="2.0"><channel>
            <item><sparkle:version>\(build)</sparkle:version><sparkle:shortVersionString>\(version)</sparkle:shortVersionString>\(extraVersion)
            <enclosure url="\(download)" length="\(length ?? archive.count)" sparkle:edSignature="\(signature)" \(enclosureVersion)/></item>
            \(extraItem)</channel></rss>
            """
        }

        func accepts(_ xml: String) throws -> Bool {
            try Data(xml.utf8).write(to: appcast)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            process.arguments = ["swift", root.appendingPathComponent("scripts/verify-appcast.swift").path,
                                 appcast.path, zip.path, plist.path, version]
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        }

        #expect(try accepts(feed()))
        #expect(try !accepts(feed(build: "122")))
        #expect(try !accepts(feed(length: archive.count + 1)))
        #expect(try !accepts(feed(url: "https://example.com/BarNook-0.1.0.zip")))
        #expect(try !accepts(feed(enclosureVersion: "sparkle:version=\"999\"")))
        let alias = "xmlns:alt=\"http://www.andymatuschak.org/xml-namespaces/sparkle\""
        #expect(try !accepts(feed(namespace: alias, enclosureVersion: "alt:version=\"0\"")))
        #expect(try !accepts(feed(namespace: alias, extraVersion: "<alt:version>0</alt:version>")))
        #expect(try !accepts(feed(extraItem: "<item/>")))

        try Data("signed archivE".utf8).write(to: zip)
        #expect(try !accepts(feed()))
    }
}
