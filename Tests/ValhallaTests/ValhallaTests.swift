import Foundation
import Testing
@testable import Valhalla

@Suite("Valhalla core safety tests")
struct ValhallaTests {
    @Test("PIT parser extracts authoritative names and filenames")
    func pitParserExtractsPartitions() {
        let output = """
        --- Entry #0 ---
        Binary Type: 0 (AP)
        Device Type: 2 (MMC)
        Partition Identifier: 7
        Partition Name: BOOT
        Flash Filename: boot.img

        --- Entry #1 ---
        Binary Type: 0 (AP)
        Partition Identifier: 8
        Partition Name: RECOVERY
        Flash Filename: recovery.img
        """

        let partitions = PITParser.parse(output)
        #expect(partitions.count == 2)
        #expect(partitions[0].identifier == 7)
        #expect(partitions[0].name == "BOOT")
        #expect(partitions[0].flashFilename == "boot.img")
        #expect(partitions[1].name == "RECOVERY")
    }

    @Test("Samsung compression suffixes normalize consistently")
    func normalizerHandlesSamsungCompressionSuffixes() {
        #expect(FilenameNormalizer.normalize("boot.img.lz4") == "boot")
        #expect(FilenameNormalizer.normalize("system.img.ext4.lz4") == "system")
        #expect(FilenameNormalizer.normalize("VENDOR_BOOT.img") == "vendorboot")
    }

    @Test("Flash planner requires a unique PIT match")
    func flashPlannerRequiresUniquePITMatch() {
        let payload = URL(fileURLWithPath: "/tmp/boot.img")
        let pit = [
            PITPartition(identifier: 7, name: "BOOT", flashFilename: "boot.img"),
            PITPartition(identifier: 8, name: "RECOVERY", flashFilename: "recovery.img")
        ]

        let plan = FlashPlanner.create(
            payloads: [payload],
            partitions: pit,
            stagingDirectory: URL(fileURLWithPath: "/tmp/staging")
        )

        #expect(plan.canFlash)
        #expect(plan.mappings.first?.partition.name == "BOOT")
    }

    @Test("Unknown payloads block the plan")
    func flashPlannerBlocksUnknownPayload() {
        let payload = URL(fileURLWithPath: "/tmp/mystery.img")
        let pit = [
            PITPartition(identifier: 7, name: "BOOT", flashFilename: "boot.img")
        ]

        let plan = FlashPlanner.create(
            payloads: [payload],
            partitions: pit,
            stagingDirectory: URL(fileURLWithPath: "/tmp/staging")
        )

        #expect(!plan.canFlash)
        #expect(plan.unmappedPayloads.map(\.lastPathComponent) == ["mystery.img"])
    }

    @Test("Appended Odin MD5 trailer is fully verified")
    func appendedMD5IsVerified() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("valhalla-md5-\(UUID().uuidString).tar.md5")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello5d41402abc4b2a76b9719d911017c592".utf8).write(to: url)

        let result = TarMD5Verifier.verifySynchronously(url)
        #expect(result == .verified)
    }

    @Test("Corrupted Odin package fails MD5 verification")
    func appendedMD5MismatchIsBlocked() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("valhalla-md5-bad-\(UUID().uuidString).tar.md5")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("HELLO5d41402abc4b2a76b9719d911017c592".utf8).write(to: url)

        let result = TarMD5Verifier.verifySynchronously(url)
        #expect(result == .mismatch)
    }
}
