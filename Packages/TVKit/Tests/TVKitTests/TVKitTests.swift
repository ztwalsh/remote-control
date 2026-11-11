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

    func testInputsAreToldApart() {
        let input = { (id: String) in LaunchPoint(id: id, title: id, iconURL: nil).isInput }
        XCTAssertTrue(input("com.webos.app.hdmi1"))
        XCTAssertTrue(input("com.webos.app.hdmi4"))
        XCTAssertTrue(input("com.webos.app.livetv"))
        XCTAssertTrue(input("com.webos.app.externalinput.av1"))
        XCTAssertFalse(input("netflix"))
        XCTAssertFalse(input("com.webos.app.lgchannels"))
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

final class WakeAddressTests: XCTestCase {
    func testPrefersWiFiAndKeepsBoth() {
        let info: JSONValue = [
            "wiredInfo": ["macAddress": "aa:bb:cc:00:00:01"],
            "wifiInfo": ["macAddress": "aa:bb:cc:00:00:02"],
        ]
        XCTAssertEqual(WebOSTV.macAddresses(in: info), ["aa:bb:cc:00:00:02", "aa:bb:cc:00:00:01"])
    }

    func testSkipsBlankAndDuplicateAddresses() {
        let info: JSONValue = [
            "wiredInfo": ["macAddress": "AA:BB:CC:00:00:02"],
            "wifiInfo": ["macAddress": "aa:bb:cc:00:00:02"],
        ]
        XCTAssertEqual(WebOSTV.macAddresses(in: info), ["aa:bb:cc:00:00:02"])
        XCTAssertEqual(WebOSTV.macAddresses(in: ["wifiInfo": ["macAddress": ""]]), [])
    }

    func testOlderPairingsStillDecode() throws {
        let old = Data(#"{"clientKey":"k","macAddress":"aa:bb:cc:00:00:01"}"#.utf8)
        let pairing = try JSONDecoder().decode(Pairing.self, from: old)
        XCTAssertNil(pairing.macAddresses)
        XCTAssertEqual(pairing.wakeAddresses, ["aa:bb:cc:00:00:01"])
    }

    func testIconsTryTheSecurePortFirst() {
        let url = URL(string: "http://192.168.1.5:3000/resources/abc/netflix.png")!
        XCTAssertEqual(SSAPClient.resourceCandidates(for: url).map(\.absoluteString), [
            "https://192.168.1.5:3001/resources/abc/netflix.png",
            "http://192.168.1.5:3000/resources/abc/netflix.png",
        ])
        let secure = URL(string: "https://192.168.1.5:3001/a.png")!
        XCTAssertEqual(SSAPClient.resourceCandidates(for: secure), [secure])
    }

    func testButtonMessage() {
        XCTAssertEqual(PointerInput.button(.up), "type:button\nname:UP\n\n")
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

    func testCleanName() {
        XCTAssertEqual(SSDP.cleanName("[LG] webOS TV OLED55C1"), "webOS TV OLED55C1")
        XCTAssertEqual(SSDP.cleanName("Living room"), "Living room")
        XCTAssertEqual(SSDP.cleanName("[LG] "), "TV")
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

final class SamsungTests: XCTestCase {
    func testConnectURLsWithTokenUseOnlyTheEncryptedPort() {
        let urls = SamsungClient.urls(host: "192.168.1.30", token: "123")
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls[0].absoluteString.hasPrefix("wss://192.168.1.30:8002/api/v2/channels/samsung.remote.control?name="))
        XCTAssertTrue(urls[0].absoluteString.hasSuffix("&token=123"))
    }

    func testConnectURLsWithoutTokenTryBothPorts() {
        for token in [nil, ""] {
            let urls = SamsungClient.urls(host: "h", token: token)
            XCTAssertEqual(urls.count, 2)
            XCTAssertTrue(urls[0].absoluteString.hasPrefix("wss://h:8002/"))
            XCTAssertTrue(urls[1].absoluteString.hasPrefix("ws://h:8001/"))
            XCTAssertFalse(urls[0].absoluteString.contains("token"))
        }
    }

    func testCatalogFindsAppsBySamsungIDOrLGAlias() {
        XCTAssertEqual(SamsungApp.entry(for: "3201907018807")?.name, "Netflix")
        XCTAssertEqual(SamsungApp.entry(for: "netflix")?.name, "Netflix")
        XCTAssertNil(SamsungApp.entry(for: "com.example.unknown"))
        // An LG alias tries every Samsung ID, newest first.
        XCTAssertEqual(SamsungApp.candidates(for: "netflix"), ["3201907018807", "11101200001"])
        // A Samsung ID tries itself first, then the entry's others.
        XCTAssertEqual(SamsungApp.candidates(for: "11101200001"), ["11101200001", "3201907018807"])
        XCTAssertEqual(SamsungApp.candidates(for: "123"), ["123"])
    }

    func testAppStatusParsing() {
        let installed = Data(#"{"id":"111299001912","name":"YouTube","running":true,"version":"1.0","visible":true}"#.utf8)
        XCTAssertEqual(SamsungAppStatus.parse(statusCode: 200, body: installed), .installed(running: true))
        XCTAssertEqual(SamsungAppStatus.parse(statusCode: 404, body: Data()), .notInstalled)
        XCTAssertEqual(SamsungAppStatus.parse(statusCode: 200, body: Data("true".utf8)), .unknown)
        XCTAssertEqual(SamsungAppStatus.parse(statusCode: 500, body: Data()), .unknown)
    }

    func testDeviceInfoParsing() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"device":{"name":"[TV] Samsung Q80 Series (55)","modelName":"QN55Q80","wifiMac":"a0:b1:c2:d3:e4:f5","PowerState":"on"},"type":"Samsung SmartTV"}
        """.utf8))
        let info = try XCTUnwrap(SamsungDeviceInfo.parse(json))
        XCTAssertEqual(info.name, "Samsung Q80 Series (55)")
        XCTAssertEqual(info.model, "QN55Q80")
        XCTAssertEqual(info.wifiMAC, "a0:b1:c2:d3:e4:f5")
        XCTAssertEqual(info.powerState, "on")
        XCTAssertNil(SamsungDeviceInfo.parse(.object(["other": "x"])))
    }

    func testButtonsMapToSamsungKeys() {
        XCTAssertEqual(SamsungTV.key(for: .enter), "KEY_ENTER")
        XCTAssertEqual(SamsungTV.key(for: .back), "KEY_RETURN")
        XCTAssertEqual(SamsungTV.key(for: .home), "KEY_HOME")
    }

    func testRenderingControlEnvelopeAndReply() {
        let body = RenderingControl.envelope("SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "12"])
        XCTAssertTrue(body.contains("<u:SetVolume xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"><InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>12</DesiredVolume></u:SetVolume>"))
        XCTAssertEqual(RenderingControl.value("CurrentVolume", in: "<s:Body><CurrentVolume>17</CurrentVolume></s:Body>"), "17")
    }

    func testDiscoveryKnowsBothBrands() {
        XCTAssertEqual(SSDP.brand(for: SSDP.searchTarget), .lg)
        XCTAssertEqual(SSDP.brand(for: SSDP.samsungSearchTarget), .samsung)
        XCTAssertNil(SSDP.brand(for: "upnp:rootdevice"))
        XCTAssertEqual(SSDP.cleanName("[TV] Samsung 7 Series"), "Samsung 7 Series")
        XCTAssertTrue(String(decoding: SSDP.searchRequest(for: SSDP.samsungSearchTarget), as: UTF8.self).contains("ST: urn:samsung.com"))
    }
}

final class VizioTests: XCTestCase {
    func testKeysLowercaseInEveryShape() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"STATUS":{"RESULT":"SUCCESS"},"ITEMS":[{"HASHVAL":12,"VALUE":31,"CNAME":"volume"}]}
        """.utf8)).lowercasedKeys()
        XCTAssertEqual(json["status"]?["result"]?.stringValue, "SUCCESS")
        XCTAssertEqual(json["items"]?.arrayValue?.first?["hashval"]?.intValue, 12)
        XCTAssertEqual(json["items"]?.arrayValue?.first?["value"]?.intValue, 31)
    }

    func testButtonsMapToPyvizioCodes() {
        XCTAssertEqual(VizioTV.key(for: .enter), VizioKey(codeset: 3, code: 2))
        XCTAssertEqual(VizioTV.key(for: .up), VizioKey(codeset: 3, code: 8))
        XCTAssertEqual(VizioTV.key(for: .home), VizioKey(codeset: 4, code: 15))
    }

    func testInputsAndAppsHaveDistinctIDs() {
        XCTAssertTrue(LaunchPoint(id: VizioTV.inputPrefix + "HDMI-1", title: "Xbox", iconURL: nil).isInput)
        let ids = VizioTV.apps.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(VizioTV.sameNamespace(2, 4))
        XCTAssertFalse(VizioTV.sameNamespace(2, 3))
    }

    func testDIALRepliesAreVizioCandidates() {
        XCTAssertEqual(SSDP.brand(for: SSDP.dialSearchTarget), .vizio)
        let description = SSDP.parseDescription("<root><friendlyName>Living Room</friendlyName><manufacturer>VIZIO</manufacturer></root>")
        XCTAssertEqual(description.manufacturer, "VIZIO")
    }
}
