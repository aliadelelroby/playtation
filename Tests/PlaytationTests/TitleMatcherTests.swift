import XCTest

final class TitleMatcherTests: XCTestCase {
    private func pick(_ query: String, from names: [String]) -> String? {
        let listings = names.enumerated().map { (id: $0.offset + 1, name: $0.element) }
        return TitleMatcher.best(query, among: listings)?.name
    }

    func testCleanDropsLauncherWordsAndBrackets() {
        XCTAssertEqual(TitleMatcher.clean("Red Dead Redemption 2 Launcher"), "Red Dead Redemption 2")
        XCTAssertEqual(TitleMatcher.clean("Hades (x64) Setup"), "Hades")
    }

    func testSequelsAreNotInterchangeable() {
        XCTAssertNil(pick("Red Dead Redemption", from: ["Red Dead Redemption 2"]))
        XCTAssertEqual(
            pick("Red Dead Redemption 2", from: ["Red Dead Redemption", "Red Dead Redemption 2"]),
            "Red Dead Redemption 2"
        )
    }

    func testPlainTitlePrefersTheOriginalOverSpinOffs() {
        let names = ["Marvel's Spider-Man: Miles Morales", "Marvel's Spider-Man Remastered", "Marvel's Spider-Man 2"]
        XCTAssertEqual(pick("Spider-Man", from: names), "Marvel's Spider-Man Remastered")
    }

    func testRequestedEditionWins() {
        let names = ["Marvel's Spider-Man Remastered", "Marvel's Spider-Man: Miles Morales"]
        XCTAssertEqual(pick("Spider-Man Miles Morales", from: names), "Marvel's Spider-Man: Miles Morales")
    }

    func testAddOnsAreRejected() {
        XCTAssertNil(pick("Hades", from: ["Hades Soundtrack", "Hades - Supporter Pack DLC"]))
        XCTAssertEqual(pick("Hades", from: ["Hades Soundtrack", "Hades"]), "Hades")
    }

    func testOneLetterTyposStillMatch() {
        XCTAssertEqual(pick("Cyberpnk 2077", from: ["Cyberpunk 2077"]), "Cyberpunk 2077")
    }

    func testPunctuationAccentsAndTrademarksAreIgnored() {
        XCTAssertEqual(pick("Witcher 3 Wild Hunt", from: ["The Witcher® 3: Wild Hunt"]), "The Witcher® 3: Wild Hunt")
        XCTAssertEqual(pick("Pokémon Legends", from: ["Pokemon Legends"]), "Pokemon Legends")
    }

    func testUnrelatedTitlesDoNotMatch() {
        XCTAssertNil(pick("Mitoza", from: ["Cyberpunk 2077", "Portal 2"]))
    }

    func testNumbersAndRomanNumeralsAgree() {
        XCTAssertTrue(TitleMatcher.compatible("Final Fantasy VII", with: "Final Fantasy 7"))
        XCTAssertFalse(TitleMatcher.compatible("Final Fantasy VIII", with: "Final Fantasy 7"))
    }

    func testCompatibleRejectsSequelForOriginal() {
        XCTAssertFalse(TitleMatcher.compatible("Marvel's Spider-Man 2", with: "Spider-Man"))
        XCTAssertTrue(TitleMatcher.compatible("Marvel's Spider-Man Remastered", with: "Spider-Man"))
    }

    func testPreferredTitleUsesInstallFolderForGenericShortcuts() {
        XCTAssertEqual(
            TitleMatcher.preferredTitle(menu: "Play", executable: "/games/Hades/Bin/Win64/Hades.exe"),
            "Hades Launcher"
        )
        XCTAssertEqual(
            TitleMatcher.preferredTitle(menu: "Spider-Man", executable: "/games/Marvel's Spider-Man Remastered/Spider-Man.exe"),
            "Marvel's Spider-Man Remastered"
        )
    }

    func testTokensSplitLettersFromNumbers() {
        XCTAssertEqual(TitleMatcher.tokens("PES2021").intersection(TitleMatcher.tokens("eFootball PES 2021")), ["pes", "2021"])
    }
}
