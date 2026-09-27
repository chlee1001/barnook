import CryptoKit
import Foundation

struct ValidationError: Error {
    let message: String
}

private let sparkleVersion = "sparkle:version"
private let sparkleShortVersion = "sparkle:shortVersionString"
private let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

private final class AppcastParser: NSObject, XMLParserDelegate {
    private(set) var channelCount = 0
    private(set) var itemCount = 0
    private(set) var enclosureCount = 0
    private(set) var enclosureAttributes: [String: String]?
    private(set) var fieldValues: [String: String] = [:]
    private(set) var failure: String?

    private var elementStack: [String] = []
    private var capturedField: (name: String, text: String)?

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        if (namespaceURI == sparkleNamespace && prefix != "sparkle") ||
           (prefix == "sparkle" && namespaceURI != sparkleNamespace) {
            failure = "Appcast must use the canonical Sparkle namespace prefix."
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard failure == nil else { return }

        let name = qName ?? elementName
        let parent = elementStack.last
        elementStack.append(name)

        switch name {
        case "rss":
            guard parent == nil, elementStack.count == 1 else {
                failure = "Appcast root element must be rss."
                return
            }
        case "channel":
            guard parent == "rss" else {
                failure = "Appcast channel is not a direct rss child."
                return
            }
            channelCount += 1
            if channelCount != 1 {
                failure = "Appcast must contain exactly one channel."
            }
        case "item":
            guard parent == "channel" else {
                failure = "Appcast item is not a direct channel child."
                return
            }
            itemCount += 1
            if itemCount != 1 {
                failure = "Appcast must contain exactly one release item."
            }
        case "enclosure":
            enclosureCount += 1
            guard parent == "item" else {
                failure = "Appcast enclosure is not a direct item child."
                return
            }
            if enclosureCount != 1 {
                failure = "Appcast must contain exactly one enclosure."
                return
            }
            enclosureAttributes = attributeDict
        case sparkleVersion, sparkleShortVersion:
            guard parent == "item" else { return }
            guard fieldValues[name] == nil, capturedField == nil else {
                failure = "Appcast contains a duplicate \(name) field."
                return
            }
            capturedField = (name, "")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard var capturedField else { return }
        capturedField.text += string
        self.capturedField = capturedField
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard failure == nil else { return }
        let name = qName ?? elementName
        guard elementStack.popLast() == name else {
            failure = "Appcast XML has an invalid element structure."
            return
        }
        guard let capturedField, capturedField.name == name else { return }
        fieldValues[capturedField.name] = capturedField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.capturedField = nil
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failure = "Appcast XML is malformed."
    }
}

private func requiredString(_ plist: [String: Any], _ key: String) throws -> String {
    guard let value = plist[key] as? String, !value.isEmpty else {
        throw ValidationError(message: "Bundle Info.plist is missing \(key).")
    }
    return value
}

private func validate(appcastPath: String, zipPath: String, plistPath: String, requestedVersion: String) throws {
    let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
    let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil)
    guard let bundleInfo = plist as? [String: Any] else {
        throw ValidationError(message: "Bundle Info.plist is not a dictionary.")
    }

    let bundleShortVersion = try requiredString(bundleInfo, "CFBundleShortVersionString")
    guard bundleShortVersion == requestedVersion else {
        throw ValidationError(message: "Bundle short version does not match the requested release.")
    }
    let bundleBuildVersion = try requiredString(bundleInfo, "CFBundleVersion")
    let publicKey = try requiredString(bundleInfo, "SUPublicEDKey")

    let parser = XMLParser(contentsOf: URL(fileURLWithPath: appcastPath))
    guard let parser else {
        throw ValidationError(message: "Cannot read appcast XML.")
    }
    let delegate = AppcastParser()
    parser.delegate = delegate
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true
    parser.shouldResolveExternalEntities = false
    guard parser.parse(), delegate.failure == nil else {
        throw ValidationError(message: delegate.failure ?? "Appcast XML is malformed.")
    }
    guard delegate.channelCount == 1 else {
        throw ValidationError(message: "Appcast must contain exactly one channel.")
    }
    guard delegate.itemCount == 1 else {
        throw ValidationError(message: "Appcast must contain exactly one release item.")
    }
    guard delegate.enclosureCount == 1, let enclosure = delegate.enclosureAttributes else {
        throw ValidationError(message: "Appcast must contain exactly one enclosure.")
    }
    guard delegate.fieldValues[sparkleShortVersion] == bundleShortVersion else {
        throw ValidationError(message: "Appcast short version does not match the bundle.")
    }
    guard delegate.fieldValues[sparkleVersion] == bundleBuildVersion else {
        throw ValidationError(message: "Appcast build version does not match the bundle.")
    }
    guard enclosure[sparkleVersion] == nil, enclosure[sparkleShortVersion] == nil else {
        throw ValidationError(message: "Appcast enclosure must not override the item versions.")
    }

    let expectedURL = "https://github.com/chlee1001/barnook/releases/download/v\(requestedVersion)/BarNook-\(requestedVersion).zip"
    guard let enclosureURL = enclosure["url"],
          let parsedURL = URL(string: enclosureURL),
          parsedURL.scheme == "https",
          parsedURL.host != nil,
          enclosureURL == expectedURL,
          parsedURL.absoluteString == expectedURL else {
        throw ValidationError(message: "Appcast enclosure URL does not match this release.")
    }

    let zipAttributes = try FileManager.default.attributesOfItem(atPath: zipPath)
    guard let zipLength = (zipAttributes[.size] as? NSNumber)?.uint64Value,
          enclosure["length"] == String(zipLength) else {
        throw ValidationError(message: "Appcast enclosure length does not match the ZIP.")
    }
    guard let signatureText = enclosure["sparkle:edSignature"],
          let signature = Data(base64Encoded: signatureText),
          signature.count == 64 else {
        throw ValidationError(message: "Appcast enclosure has an invalid Ed25519 signature.")
    }
    guard let publicKeyData = Data(base64Encoded: publicKey), publicKeyData.count == 32 else {
        throw ValidationError(message: "Bundle SUPublicEDKey is not a valid Ed25519 public key.")
    }

    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let zipData = try Data(contentsOf: URL(fileURLWithPath: zipPath))
    guard key.isValidSignature(signature, for: zipData) else {
        throw ValidationError(message: "Appcast Ed25519 signature does not match the ZIP.")
    }
}

guard CommandLine.arguments.count == 5 else {
    fputs("usage: verify-appcast.swift APPCAST ZIP BUNDLE_INFO_PLIST VERSION\n", stderr)
    exit(2)
}

do {
    try validate(
        appcastPath: CommandLine.arguments[1],
        zipPath: CommandLine.arguments[2],
        plistPath: CommandLine.arguments[3],
        requestedVersion: CommandLine.arguments[4]
    )
} catch let error as ValidationError {
    fputs("Appcast validation failed: \(error.message)\n", stderr)
    exit(1)
} catch {
    fputs("Appcast validation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
