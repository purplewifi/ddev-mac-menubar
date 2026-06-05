import Foundation
import Testing
@testable import ddev_menubar

struct DdevProjectDecodingTests {
    @Test func decodesListProjectPayload() throws {
        let json = """
        {
          "name": "portal",
          "approot": "/Users/alan/Projects/portal",
          "shortroot": "~/Projects/portal",
          "status": "running",
          "status_desc": "running",
          "type": "laravel",
          "primary_url": "https://portal.ddev.site",
          "httpurl": "http://portal.ddev.site",
          "httpsurl": "https://portal.ddev.site",
          "mailpit_url": "http://portal.ddev.site:8025",
          "nodejs_version": "24",
          "docroot": "public",
          "mutagen_enabled": true,
          "mutagen_status": "ok"
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(DdevProject.self, from: json)

        #expect(project.name == "portal")
        #expect(project.isRunning)
        #expect(project.primaryURL == "https://portal.ddev.site")
    }
}

struct DdevProjectGroupTests {
    @Test func encodesAndDecodesGroups() throws {
        let group = DdevProjectGroup(name: "Portal stack", projectNames: ["portal", "portal-client"])
        let data = try JSONEncoder().encode([group])
        let decoded = try JSONDecoder().decode([DdevProjectGroup].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Portal stack")
        #expect(decoded[0].projectNames == ["portal", "portal-client"])
    }
}
