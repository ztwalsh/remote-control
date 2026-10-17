import XCTest
@testable import TVKit

final class JSONValueTests: XCTestCase {
    func testRoundTrip() throws {
        let value: JSONValue = ["volume": 20, "mute": false, "id": "netflix", "list": [1, "two"], "none": .null]
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
    }

    func testWholeNumbersEncodeAsIntegers() throws {
        let data = try JSONEncoder().encode(JSONValue.number(20))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "20")
    }

    func testBooleansStayBooleans() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":true,"b":1}"#.utf8))
        XCTAssertEqual(decoded["a"], .bool(true))
        XCTAssertEqual(decoded["b"], .number(1))
    }
}

final class SSAPMessageTests: XCTestCase {
    func testRequestEncoding() throws {
        let message = SSAPOutgoing(type: "request", id: "req_1", uri: SSAPURI.setVolume, payload: ["volume": 12])
        let object = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(object["type"], "request")
        XCTAssertEqual(object["id"], "req_1")
        XCTAssertEqual(object["uri"]?.stringValue, "ssap://audio/setVolume")
        XCTAssertEqual(object["payload"]?["volume"]?.intValue, 12)
    }

    func testOptionalFieldsAreOmitted() throws {
        let text = String(decoding: try JSONEncoder().encode(SSAPOutgoing(type: "unsubscribe", id: "req_2")), as: UTF8.self)
        XCTAssertFalse(text.contains("uri"))
        XCTAssertFalse(text.contains("payload"))
    }

    func testRegistrationIncludesClientKeyOnlyWhenKnown() {
        XCTAssertNil(SSAPRegistration.payload(clientKey: nil)["client-key"])
        XCTAssertEqual(SSAPRegistration.payload(clientKey: "abc")["client-key"], "abc")
        XCTAssertEqual(SSAPRegistration.payload(clientKey: nil)["pairingType"], "PROMPT")
    }

    func testIncomingDecoding() throws {
        let json = #"{"type":"response","id":"req_3","payload":{"returnValue":true,"volume":9,"muted":true}}"#
        let message = try JSONDecoder().decode(SSAPIncoming.self, from: Data(json.utf8))
        XCTAssertEqual(message.id, "req_3")
        XCTAssertEqual(message.payload?["volume"]?.intValue, 9)
    }
}

final class ModelParsingTests: XCTestCase {
    func testVolumeOlderShape() {
        let status = VolumeStatus.parse(["volume": 14, "muted": true])
        XCTAssertEqual(status, VolumeStatus(level: 14, muted: true))
    }

    func testVolumeNewerShape() {
        let status = VolumeStatus.parse(["volumeStatus": ["volume": 30, "muteStatus": false, "soundOutput": "external_arc"]])
        XCTAssertEqual(status, VolumeStatus(level: 30, muted: false, soundOutput: .hdmiARC))
    }

    func testVolumeMissing() {
        XCTAssertNil(VolumeStatus.parse(["returnValue": true]))
    }

    func testSoundOutputKeepsUnknownNames() {
        XCTAssertEqual(SoundOutput(rawValue: "tv_speaker"), .tvSpeaker)
        XCTAssertEqual(SoundOutput(rawValue: "lineout"), .other("lineout"))
        XCTAssertEqual(SoundOutput.other("lineout").rawValue, "lineout")
        XCTAssertEqual(SoundOutput.hdmiARC.rawValue, "external_arc")
    }

    func testLaunchPoints() {
        let payload: JSONValue = ["launchPoints": [
            ["id": "netflix", "title": "Netflix", "icon": "http://192.168.1.5:3000/netflix.png"],
            ["title": "No ID"],
        ]]
        let points = LaunchPoint.parseList(payload)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.id, "netflix")
        XCTAssertEqual(points.first?.iconURL?.lastPathComponent, "netflix.png")
    }
}

final class WakeOnLANTests: XCTestCase {
    func testMagicPacket() throws {
        let packet = try WakeOnLAN.magicPacket(macAddress: "A8:23:FE:01:02:03")
        XCTAssertEqual(packet.count, 6 + 16 * 6)
        XCTAssertEqual(Array(packet.prefix(6)), Array(repeating: 0xFF, count: 6))
        XCTAssertEqual(Array(packet[6..<12]), [0xA8, 0x23, 0xFE, 0x01, 0x02, 0x03])
        XCTAssertEqual(Array(packet.suffix(6)), [0xA8, 0x23, 0xFE, 0x01, 0x02, 0x03])
    }

    func testAcceptsDashes() throws {
        XCTAssertNoThrow(try WakeOnLAN.magicPacket(macAddress: "a8-23-fe-01-02-03"))
    }

    func testRejectsBadAddresses() {
        XCTAssertThrowsError(try WakeOnLAN.magicPacket(macAddress: "A8:23:FE"))
    }
}

final class SSDPTests: XCTestCase {
    func testParsesReply() {
        let reply = "HTTP/1.1 200 OK\r\nCache-Control: max-age=1800\r\nlocation: http://192.168.1.20:1754/\r\n" +
            "ST: urn:lge-com:service:webos-second-screen:1\r\nUSN: uuid:1234::urn:lge-com:service:webos-second-screen:1\r\n\r\n"
        let response = SSDP.parse(reply)
        XCTAssertEqual(response?.location?.absoluteString, "http://192.168.1.20:1754/")
        XCTAssertEqual(response?.searchTarget, SSDP.searchTarget)
        XCTAssertEqual(response?.usn, "uuid:1234::urn:lge-com:service:webos-second-screen:1")
    }

    func testIgnoresNonReplies() {
        XCTAssertNil(SSDP.parse("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n\r\n"))
    }

    func testSearchRequest() {
        let text = String(decoding: SSDP.searchRequest, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("ST: urn:lge-com:service:webos-second-screen:1"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"))
    }

    func testDescription() {
        let xml = "<root><device><friendlyName>Living room</friendlyName><modelName>OLED65C3</modelName></device></root>"
        let description = SSDP.parseDescription(xml)
        XCTAssertEqual(description.name, "Living room")
        XCTAssertEqual(description.model, "OLED65C3")
    }
}

final class MockTVTests: XCTestCase {
    func testVolumeIsClampedAndBroadcast() async throws {
        let tv = MockTV(volume: 10)
        let events = await tv.events()
        try await tv.setVolume(140)
        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()
        XCTAssertEqual(event, .volume(VolumeStatus(level: 100, muted: false, soundOutput: .tvSpeaker)))
    }
}
