import Foundation

/// Every sentence here keeps the exact shape of a real one. The conversions are
/// transcripts the cleanup model left unformatted; the refusals are transcripts
/// that would have been corrupted by a looser rule. Both sets come from the same
/// 9,401-dictation corpus, which is the only reason to trust either — names and
/// private details are swapped for neutral ones of identical grammar, since the
/// test earns its keep from the structure and this repository is public.
enum SpokenMoneyTests {
    static func run() {
        testTheCasesTheModelMisses()
        testNumberWords()
        testIdiomsAreNotAmounts()
        testWeightIsNotMoney()
        testHyphenatedCompoundsConvertWhole()
        testTheAmbiguousSuffixIsLeftToTheModel()
        testOrdinaryProseIsUntouched()
        testPunctuationSurvives()
        testSeveralAmountsInOneSentence()
        testIdempotent()
        testMultiWordNumbersConvertWhole()
        testEveryLineConverts()
        testArticleStaysWithTheNounItBelongsTo()
        testCapitalisedCurrencyWordsAreProperNouns()
        testVaguenessAndPossessivesAreLeftAlone()
        testWrittenNumberFormats()
    }

    /// The 17x error. "eighty five bucks" reading as "eighty $5" is worse than
    /// no conversion at all, because it still looks like ordinary text.
    private static func testMultiWordNumbersConvertWhole() {
        expect(SpokenMoney.format("they're charging me eighty five bucks a month"),
               "they're charging me $85 a month")
        expect(SpokenMoney.format("twenty five hundred dollars for the whole build"),
               "$2,500 for the whole build")
        expect(SpokenMoney.format("the retainer is two thousand five hundred dollars"),
               "the retainer is $2,500")
        expect(SpokenMoney.format("it came to four hundred eighty dollars"), "it came to $480")
        expect(SpokenMoney.format("a hundred and twenty dollars a month"), "$120 a month")
        expect(SpokenMoney.format("ninety nine dollars"), "$99")
        // The space-separated twin of the hyphenated case above.
        expect(SpokenMoney.format("thirty nine dollar a month plan"), "$39 a month plan")
        // Digits stay self-contained — this is two facts, not one number.
        expect(SpokenMoney.format("for 2 hours 30 dollars"), "for 2 hours $30")
        // A phrase cannot run across sentence punctuation.
        expect(SpokenMoney.format("give me five, ten dollars"), "give me five, $10")
    }

    /// The Smart path hands the model's own output to `finishText` without
    /// collapsing whitespace, and the prompt asks it to render spoken bullets as
    /// real lines. Splitting on a literal " " converted only the last one.
    private static func testEveryLineConverts() {
        expect(SpokenMoney.format("- Claude Max 20 dollars\n- Cursor 20 dollars\n- Linear 8 dollars"),
               "- Claude Max $20\n- Cursor $20\n- Linear $8")
        expect(SpokenMoney.format("1. Hosting 40 dollars\n2. Domain 12 dollars"),
               "1. Hosting $40\n2. Domain $12")
        // Whitespace is reproduced exactly, not normalised.
        expect(SpokenMoney.format("  40 dollars  \n\n  20 bucks "), "  $40  \n\n  $20 ")
    }

    /// "a hundred dollars" is $100, but the "a" in "a thousand dollar retainer"
    /// belongs to the retainer.
    private static func testArticleStaysWithTheNounItBelongsTo() {
        expect(SpokenMoney.format("they want a thousand dollar retainer"),
               "they want a $1,000 retainer")
        expect(SpokenMoney.format("he broke a hundred dollar bill"), "he broke a $100 bill")
        expect(SpokenMoney.format("it's a hundred dollar a month plan"), "it's a $100 a month plan")
        // Plural: the article is part of the amount.
        expect(SpokenMoney.format("a budget of a hundred dollars"), "a budget of $100")
        // A bare article is not a number.
        expect(SpokenMoney.format("give him a dollar"), "give him a dollar")
    }

    private static func testCapitalisedCurrencyWordsAreProperNouns() {
        for sentence in [
            "I went to three Dollar General stores",
            "two Dollar Tree locations near me",
            "I watched two Bucks games last night",
        ] {
            expect(SpokenMoney.format(sentence), sentence)
        }
    }

    /// A vague quantity must not acquire a precise figure, and a possessive has
    /// nowhere to put its apostrophe.
    private static func testVaguenessAndPossessivesAreLeftAlone() {
        for sentence in [
            "a couple hundred dollars",
            "several thousand dollars",
            "it was worth thousands of dollars",
            "twenty dollars' worth of credits",
        ] {
            expect(SpokenMoney.format(sentence), sentence)
        }
        // But an explicit multiplier still converts.
        expect(SpokenMoney.format("one hundred thousand dollars"), "$100,000")
        expect(SpokenMoney.format("two hundred dollars"), "$200")
    }

    private static func testWrittenNumberFormats() {
        expect(SpokenMoney.format("per inbox it's 3.50 dollars"), "per inbox it's $3.50")
        expect(SpokenMoney.format("25,000 dollars for the year"), "$25,000 for the year")
        // European decimal comma must not read as grouping — 3,50 is not 350.
        expect(SpokenMoney.format("3,50 dollars"), "3,50 dollars")
        // A leading zero is a reference number, not a price.
        expect(SpokenMoney.format("007 dollars"), "007 dollars")
        // Malformed grouping is refused rather than guessed at.
        expect(SpokenMoney.format("25,00 dollars"), "25,00 dollars")
    }

    /// The 22 of 28 the model left alone. These are the reason the pass exists.
    private static func testTheCasesTheModelMisses() {
        expect(SpokenMoney.format("So I just made a 25 second scene and it cost me over 40 dollars."),
               "So I just made a 25 second scene and it cost me over $40.")
        expect(SpokenMoney.format("I've been charged 140 bucks, but I don't have any invoices"),
               "I've been charged $140, but I don't have any invoices")
        expect(SpokenMoney.format("the account is topped up with 30 dollars loaded."),
               "the account is topped up with $30 loaded.")
        expect(SpokenMoney.format("would you be able to make an account here, add like 20 bucks"),
               "would you be able to make an account here, add like $20")
        // Singular "dollar" used adjectivally still names an amount.
        expect(SpokenMoney.format("the 200 dollar a month subscription plan"),
               "the $200 a month subscription plan")
        expect(SpokenMoney.format("It's 25,000 credits for 59 bucks."),
               "It's 25,000 credits for $59.")
    }

    private static func testNumberWords() {
        expect(SpokenMoney.format("a budget of a hundred dollars total"), "a budget of $100 total")
        expect(SpokenMoney.format("the going rate was a thousand dollars."),
               "the going rate was $1,000.")
        expect(SpokenMoney.format("Don't spend more than five dollars though."),
               "Don't spend more than $5 though.")
        expect(SpokenMoney.format("Ten dollars total. Max amount able to be used."),
               "$10 total. Max amount able to be used.")
        expect(SpokenMoney.format("I just had twenty dollars in API credits"),
               "I just had $20 in API credits")
        expect(SpokenMoney.format("five hundred dollars"), "$500")
        expect(SpokenMoney.format("two thousand dollars"), "$2,000")
    }

    /// "million dollar" is a compliment, not a price.
    private static func testIdiomsAreNotAmounts() {
        for sentence in [
            "Million dollar sass right there.",
            "I'm automating it for them and they're multi-million dollar business.",
            "that's the billion dollar question",
        ] {
            expect(SpokenMoney.format(sentence), sentence)
        }
    }

    /// The single most dangerous collision, and the reason pounds are not
    /// handled: "How many pounds would that feel like" is in the same sentence.
    private static func testWeightIsNotMoney() {
        let sentence = "How easy would it be to move a 200 pound stone in relation to what they did for me?"
        expect(SpokenMoney.format(sentence), sentence)
        expect(SpokenMoney.format("it weighs 40 pounds"), "it weighs 40 pounds")
        expect(SpokenMoney.format("that costs 40 euros"), "that costs 40 euros")
    }

    /// Matching only the tail of "Thirty-nine" would write "Thirty-$9".
    private static func testHyphenatedCompoundsConvertWhole() {
        expect(SpokenMoney.format("the Thirty-nine dollar a month plan is equal in usage"),
               "the $39 a month plan is equal in usage")
        expect(SpokenMoney.format("twenty-five bucks"), "$25")
        // A hyphenated non-number is not a number.
        expect(SpokenMoney.format("the pay-per dollar model"), "the pay-per dollar model")
    }

    /// 56 of the 85 corpus cases use a bare "k", and it is genuinely ambiguous —
    /// these four sentences are all real and only two of them are money.
    private static func testTheAmbiguousSuffixIsLeftToTheModel() {
        for sentence in [
            "that has 145k followers on Instagram and is pretty big.",
            "does the system get at least 2k usable leads per day",
            "I just closed Alex Foster for 2k.",
            "paying us 10k a month",
        ] {
            expect(SpokenMoney.format(sentence), sentence)
        }
    }

    private static func testOrdinaryProseIsUntouched() {
        for sentence in [
            "the dollar is up against the euro",
            "we got top dollar for it",
            "dollar for dollar it's the better tool",
            "per inbox it's 3.50 depending on how many they want",
            "in 2020 dollars that's a lot",           // inflation-adjusted, not $2,020
            "it already says $40 here",               // the model's own output
            "",
        ] {
            expect(SpokenMoney.format(sentence), sentence)
        }
    }

    private static func testPunctuationSurvives() {
        expect(SpokenMoney.format("it's worth 50 dollars."), "it's worth $50.")
        expect(SpokenMoney.format("charged 140 bucks, then refunded"), "charged $140, then refunded")
        expect(SpokenMoney.format("(about 20 bucks)"), "(about $20)")
    }

    private static func testSeveralAmountsInOneSentence() {
        expect(SpokenMoney.format("it ends up being like 10 dollars an hour or five dollars an hour."),
               "it ends up being like $10 an hour or $5 an hour.")
        expect(SpokenMoney.format("all of them on Cloudflare for five bucks a month or a similar server for less than ten bucks a month."),
               "all of them on Cloudflare for $5 a month or a similar server for less than $10 a month.")
    }

    /// `finishText` is not re-entered, but the corrections re-apply means the
    /// text can pass through here after already being rewritten once.
    private static func testIdempotent() {
        for sentence in ["it cost me over 40 dollars.", "a budget of a hundred dollars total",
                         "Million dollar sass right there.", "that has 145k followers"] {
            let once = SpokenMoney.format(sentence)
            expect(SpokenMoney.format(once), once)
        }
    }

    private static func expect(_ actual: String, _ expected: String, file: StaticString = #file, line: UInt = #line) {
        if actual != expected {
            fatalError("\(file):\(line): SpokenMoney: expected \"\(expected)\" but got \"\(actual)\"")
        }
    }
}
