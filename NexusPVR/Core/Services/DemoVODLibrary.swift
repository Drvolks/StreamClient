//
//  DemoVODLibrary.swift
//  PVR Client
//
//  The On Demand library shown in demo mode (#17): a few movies and
//  multi-season series, none of them real.
//

import Foundation

nonisolated enum DemoVODLibrary {

    // MARK: - Titles

    static let titles: [DemoVODTitle] = movies + series

    private static let movies: [DemoVODTitle] = [
        DemoVODTitle(
            id: 5001, kind: .movies, name: "The Fast and the Curious", year: 2019, rating: "PG",
            genre: "Action, Comedy", category: "Action & Adventure", minutes: 107,
            plot: "A driving instructor with a need for answers pursues the one student who has never, not once, used a turn signal. The chase tops out at 38 km/h.",
            director: "Justin Linger", actors: "Vin Petrol, Paula Walkman, Michelle Roadrageuez",
            poster: "demo_vod_fast_curious_poster.jpg", backdrop: "demo_vod_fast_curious_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5002, kind: .movies, name: "Paranormal Accountant", year: 2021, rating: "14A",
            genre: "Horror, Comedy", category: "Thrillers & Chillers", minutes: 94,
            plot: "The receipts are moving on their own. A night auditor discovers that a 1987 expense report was never approved — and it wants closure.",
            director: "Oren Ledger", actors: "Katie Fiscal, Micah Sloane-Deductible",
            poster: "demo_vod_paranormal_accountant_poster.jpg", backdrop: "demo_vod_paranormal_accountant_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5003, kind: .movies, name: "Mission: Improbable", year: 2018, rating: "PG",
            genre: "Action, Thriller", category: "Action & Adventure", minutes: 128,
            plot: "Agent Ethan Hunch has one night to return a library book that is twenty-two years overdue. The late fee could bring down a government.",
            director: "Christopher McQuarrel", actors: "Tom Snooze, Rebecca Fergusoon, Ving Rhymes",
            poster: "demo_vod_mission_improbable_poster.jpg", backdrop: "demo_vod_mission_improbable_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5004, kind: .movies, name: "Lord of the Onion Rings", year: 2003, rating: "PG",
            genre: "Fantasy, Adventure", category: "Action & Adventure", minutes: 201,
            plot: "One ring to fry them all. A reluctant line cook must carry the last onion ring across the food court and cast it back into the deep fryer where it was made.",
            director: "Peter Snackson", actors: "Elijah Would, Sir Ian McKettle, Viggo Morsel",
            poster: "demo_vod_onion_rings_poster.jpg", backdrop: "demo_vod_onion_rings_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5005, kind: .movies, name: "Jurassic Parking", year: 2015, rating: "PG",
            genre: "Adventure, Sci-Fi", category: "Action & Adventure", minutes: 124,
            plot: "The dinosaurs were never the problem. Four thousand visitors, one hundred and twelve parking spots, and a velociraptor who has learned to validate tickets.",
            director: "Colin Towaway", actors: "Chris Spratt, Bryce Dallas Coward, Jeff Goldbloom",
            poster: "demo_vod_jurassic_parking_poster.jpg", backdrop: "demo_vod_jurassic_parking_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5006, kind: .movies, name: "The Silence of the Yams", year: 1991, rating: "14A",
            genre: "Thriller", category: "Thrillers & Chillers", minutes: 118,
            plot: "A rookie produce inspector consults a brilliant, imprisoned chef to work out why the root vegetables at the farmers' market have stopped talking.",
            director: "Jonathan Dimmer", actors: "Jodie Roster, Anthony Hopkiln",
            poster: "demo_vod_silence_yams_poster.jpg", backdrop: "demo_vod_silence_yams_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5007, kind: .movies, name: "Gone with the Wi-Fi", year: 2022, rating: "G",
            genre: "Drama, Romance", category: "Drama", minutes: 142,
            plot: "When the router dies during a snowstorm, a family of five is forced to endure forty-eight hours of eye contact. Frankly, my dear, the modem doesn't give a ping.",
            director: "Victoria Flemish", actors: "Clark Cable, Vivien Lag",
            poster: "demo_vod_gone_wifi_poster.jpg", backdrop: "demo_vod_gone_wifi_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5008, kind: .movies, name: "A Fistful of Coupons", year: 1964, rating: "PG",
            genre: "Western", category: "Drama", minutes: 99,
            plot: "A stranger with no name and a binder full of expired savings rides into a town where two rival grocers refuse to price-match.",
            director: "Sergio Leoni", actors: "Clint Westwood, Gian Maria Bolognese",
            poster: "demo_vod_fistful_coupons_poster.jpg", backdrop: "demo_vod_fistful_coupons_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5009, kind: .movies, name: "Sharkcano vs. Mild Weather", year: 2020, rating: "14A",
            genre: "Disaster, Comedy", category: "Comedy", minutes: 88,
            plot: "A volcano full of sharks threatens the coast. Fortunately the forecast calls for light drizzle and a pleasant breeze, and the sharks find it all very calming.",
            director: "Anthony C. Ferrantic", actors: "Ian Zeering, Tara Reef",
            poster: "demo_vod_sharkcano_poster.jpg", backdrop: "demo_vod_sharkcano_backdrop.jpg"
        ),
        DemoVODTitle(
            id: 5010, kind: .movies, name: "Extreme Ironing: The Movie", year: 2024, rating: "PG",
            genre: "Sports, Documentary", category: "Comedy", minutes: 96,
            plot: "The true story of the team that pressed a dress shirt on the summit of a mountain, mid-avalanche, with no starch. Based on the hit championship broadcast.",
            director: "Flat Stanley Kubrick", actors: "Steam Jobs, Wrinkle Kidman",
            poster: "demo_vod_extreme_ironing_poster.jpg", backdrop: "demo_vod_extreme_ironing_backdrop.jpg"
        ),
    ]

    private static let series: [DemoVODTitle] = [
        DemoVODTitle(
            id: 6001, kind: .series, name: "The Quantum Detective", year: 2022, rating: "TV-14",
            genre: "Sci-Fi, Mystery", category: "Drama", minutes: 52,
            plot: "Detective Marsh solves every case and simultaneously doesn't. Until someone opens the evidence box, the butler both did it and has a solid alibi.",
            poster: "demo_series_quantum_poster.png", backdrop: "demo_series_quantum_fanart.png",
            seasons: [
                [
                    ("Schrödinger's Witness", "The only witness to a jewel heist is a cat who may or may not have been in the room."),
                    ("Spooky Action at a Crime Scene", "Two fingerprints, eleven light-years apart, belong to the same thumb."),
                    ("The Uncertainty Principal", "A school principal is definitely missing, but nobody can say how fast."),
                    ("Entangled", "Marsh's ex-partner is back, and every time he lies, she sneezes."),
                    ("Wave Goodbye", "The suspect collapses into a single location the moment somebody looks at him."),
                    ("Dead and Alive", "The season's victim files a complaint about the investigation into his own murder."),
                ],
                [
                    ("The Many Worlds Interrogation", "Marsh questions a suspect in every universe where she agreed to come downtown."),
                    ("Planck Length Arm of the Law", "A very, very small crime rocks the department."),
                    ("Superposition of Trust", "Internal Affairs is investigating Marsh, and also is Marsh."),
                    ("A Brief History of Crime", "A time-travelling pickpocket returns everything he hasn't stolen yet."),
                    ("Tunnel Vision", "The getaway driver drove straight through a wall. The wall has no comment."),
                    ("The Observer Effect", "The stakeout fails because watching the house changed where the house is."),
                ],
                [
                    ("Half-Life Sentence", "A prisoner is released exactly halfway, then halfway again."),
                    ("Heisenberg's Alibi", "The suspect knows exactly where he was, which means he has no idea when."),
                    ("Quark and Dagger", "A particle physicist is stabbed with something that has no mass."),
                    ("String Theory of the Case", "Marsh's evidence board needs eleven dimensions of red yarn."),
                    ("Dark Matters", "Ninety-five percent of the evidence is missing and always has been."),
                    ("The Parallel Alibi", "A murder suspect was provably in two cities at the same time."),
                ],
            ]
        ),
        DemoVODTitle(
            id: 6002, kind: .series, name: "Game of Thermostats", year: 2019, rating: "TV-PG",
            genre: "Drama, Comedy", category: "Drama", minutes: 58,
            plot: "Winter is coming, and so is the heating bill. In a draughty split-level, five family members wage a merciless war over one small dial on the hallway wall.",
            poster: "demo_vod_thermostats_poster.jpg", backdrop: "demo_vod_thermostats_backdrop.jpg",
            seasons: [
                [
                    ("Winter Is Coming, Put On a Sweater", "Dad discovers the dial has been moved to 23 and swears an oath."),
                    ("The Hallway Road", "An alliance forms between the basement and the upstairs bedroom."),
                    ("Lord Programmable", "A smart thermostat arrives. Nobody knows who holds the password."),
                    ("A Draught of Ice and Fire", "Grandma opens a window in January, for the air."),
                    ("You Win or You Shiver", "The season ends with a blanket nobody is willing to share."),
                ],
                [
                    ("The North Bedroom Remembers", "The coldest room in the house demands recognition."),
                    ("Blackwater Heater", "The hot water runs out during a critical shower."),
                    ("The Prince of Space Heaters", "A teenager brings a forbidden appliance into the realm."),
                    ("What Is Dead May Never Defrost", "Somebody finds what has been in the chest freezer since 2011."),
                    ("Valar Eco-Mode", "All men must economize."),
                ],
                [
                    ("The Rains of Air Conditioning", "Summer arrives and every alliance reverses overnight."),
                    ("Kissed by Fan", "An oscillating fan becomes the most powerful object in the kitchen."),
                    ("The Bill and the Maiden", "The utility statement arrives. A messenger is blamed."),
                    ("Second Sons, First Floor", "The middle child claims the room with the good vent."),
                    ("Mhysa Remote", "The remote for the wall unit is found, far too late."),
                ],
                [
                    ("The Long Nightlight", "A power cut plunges the house into honest conversation."),
                    ("A Knight of the Seven Settings", "A repair technician is treated as visiting royalty."),
                    ("The Bells of the Furnace", "It starts making that noise again."),
                    ("The Last of the Fleece", "There is one warm blanket left, and four people on the couch."),
                    ("The Iron Dial", "Someone finally sits on the armchair beside the thermostat. Reviews are mixed."),
                ],
            ]
        ),
        DemoVODTitle(
            id: 6003, kind: .series, name: "Breaking Bread", year: 2020, rating: "TV-14",
            genre: "Drama, Crime", category: "Drama", minutes: 47,
            plot: "A mild-mannered chemistry teacher learns he makes the purest sourdough in the south-west. Say his name: it's on the bakery awning.",
            poster: "demo_vod_breaking_bread_poster.jpg", backdrop: "demo_vod_breaking_bread_backdrop.jpg",
            seasons: [
                [
                    ("Pilot Light", "Walter proofs his first loaf in the back of a motorhome."),
                    ("Crust in the Bag", "A rival bakery sends a message. It's a baguette. It's stale."),
                    ("...And the Dough's in the River", "A whole batch has to disappear before the health inspector arrives."),
                    ("Gluten Man", "Walter insists he is in the bread business, not the flour business."),
                    ("Crazy Handful of Raisins", "Jesse adds raisins without asking, and there are consequences."),
                    ("A No-Rough-Stuff-Type Meal", "A simple brunch order gets out of hand."),
                ],
                [
                    ("Seven Thirty-Seven Grain", "The new loaf has a lot of seeds in it."),
                    ("Better Call Salt", "A lawyer explains that the starter is, legally, a pet."),
                    ("Four Days Proofing", "Walter and Jesse are stranded in the desert with nothing but a dutch oven."),
                    ("I Am the One Who Kneads", "Walter clarifies his role in the organisation."),
                    ("Half Measures of Flour", "A lesson about weighing your ingredients, delivered in a car park."),
                    ("Full Baker's Dozen", "Thirteen is the number. It was always the number."),
                ],
            ]
        ),
        DemoVODTitle(
            id: 6004, kind: .series, name: "House of Cardigans", year: 2021, rating: "TV-PG",
            genre: "Drama, Comedy", category: "Comedy", minutes: 44,
            plot: "Power. Betrayal. Merino. A ruthless treasurer will stop at nothing to become president of the Tuesday-afternoon knitting circle.",
            poster: "demo_vod_cardigans_poster.jpg", backdrop: "demo_vod_cardigans_backdrop.jpg",
            seasons: [
                [
                    ("Chapter Purl", "Frances is passed over for the cable-knit committee and looks directly at the camera."),
                    ("A Stitch in Time", "A leaked pattern destroys a promising cardigan career."),
                    ("Dropping a Stitch", "Somebody has been tampering with the communal yarn."),
                    ("The Whip Stitch", "Frances counts votes for the bake sale and finds she is two short."),
                    ("Casting Off", "The president resigns over the acrylic scandal."),
                ],
                [
                    ("Yarn Over", "A new member arrives who can crochet, which is technically allowed."),
                    ("The Gauge Swatch", "An investigation into why the charity scarf is four metres long."),
                    ("Blocking", "Frances pins down the opposition, and a damp shawl."),
                    ("Moth Season", "There is a mole in the knitting circle. Also moths."),
                    ("Bind Off", "The annual general meeting runs to almost forty minutes."),
                ],
                [
                    ("Intarsia", "Alliances shift as the circle attempts a reindeer."),
                    ("Second Sock Syndrome", "Nobody ever finishes the second one, and Frances knows why."),
                    ("Frogging", "Rip it, rip it. An entire season's work is unravelled in one evening."),
                    ("Steek", "A cardigan is cut straight down the middle, on purpose, in front of everyone."),
                    ("The Final Row", "Frances takes the big chair by the radiator."),
                ],
            ]
        ),
        DemoVODTitle(
            id: 6005, kind: .series, name: "The Great Canadian Shovel-Off", year: 2023, rating: "TV-G",
            genre: "Reality, Competition", category: "Reality", minutes: 41,
            plot: "Twelve amateur shovellers, one endless driveway. Judged on speed, edge crispness, and how sincerely they apologise to the snow.",
            poster: "demo_vod_shovel_off_poster.jpg", backdrop: "demo_vod_shovel_off_backdrop.jpg",
            seasons: [
                [
                    ("Powder Week", "The contestants meet the driveway. One of them brought a leaf blower."),
                    ("The Plough Wall", "The city plough passes at dawn and undoes everything."),
                    ("Ice Week", "Salt is rationed. Tempers are not."),
                    ("Sorry, You Go Ahead", "Two finalists spend eleven minutes letting each other go first."),
                    ("The Final Flurry", "A champion is crowned and handed a double-double."),
                ],
                [
                    ("Heavy Wet Stuff", "A new season opens with the worst kind of snow."),
                    ("Neighbour Week", "Contestants must shovel the driveway next door without being asked."),
                    ("The Roof Rake", "A controversial new tool divides the judges."),
                    ("Freezing Rain Delay", "Filming stops. Everyone goes inside for soup."),
                    ("The Polar Vortex Final", "It is -41 with the wind chill and the shovels are singing."),
                ],
            ]
        ),
        DemoVODTitle(
            id: 6006, kind: .series, name: "Stand-Up Spotlight", year: 2024, rating: "TV-14",
            genre: "Comedy", category: "Comedy", minutes: 28,
            plot: "New comedians, one microphone, and a stool nobody ever sits on. Recorded in front of a live audience that was promised free nachos.",
            poster: "demo_series_spotlight_image.png", backdrop: "demo_series_spotlight_fanart.png",
            seasons: [
                [
                    ("Airline Food, Revisited", "A comedian finally gets to the bottom of what the deal is."),
                    ("My Roommate, the Printer", "Seven minutes on a machine that only works when watched."),
                    ("Self-Checkout", "An unexpected item is in the bagging area. It's her dignity."),
                    ("Group Chat", "Forty-one unread messages and none of them say where dinner is."),
                    ("The Heckler Special", "The audience member in row two gets his own set."),
                ],
                [
                    ("Password Must Contain", "A special character, a number, and a piece of your soul."),
                    ("Ikea Maze", "A couple enters on Saturday morning. The marriage exits on Sunday."),
                    ("Reply All", "A cautionary tale performed entirely in the passive-aggressive voice."),
                    ("Hold Music", "Your call is important to us. A man loses a decade."),
                    ("Encore, Please Clap", "The season finale, with the stool finally used."),
                ],
            ]
        ),
    ]

    // MARK: - Browse

    static var counts: VODCounts {
        VODCounts(movies: movies.count, series: series.count)
    }

    static func categories(kind: VODKind) -> [VODCategory] {
        let names = Set(titles.filter { $0.kind == kind }.map(\.category)).sorted()
        return names.enumerated().map { index, name in
            VODCategory(id: (kind == .movies ? 100 : 200) + index, name: name, categoryType: kind.categoryType)
        }
    }

    /// Mirrors the server's list endpoints: name order, `search` over name,
    /// description and genre, `category` as "Name|type".
    static func page(kind: VODKind, page: Int, pageSize: Int, search: String?, category: String?) -> VODPage {
        var matches = titles.filter { $0.kind == kind }
        if let query = search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty {
            matches = matches.filter {
                [$0.name, $0.plot, $0.genre].contains { $0.lowercased().contains(query) }
            }
        }
        if let categoryName = category?.split(separator: "|").first.map(String.init), !categoryName.isEmpty {
            matches = matches.filter { $0.category == categoryName }
        }
        matches.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let size = max(pageSize, 1)
        let start = (max(page, 1) - 1) * size
        let slice = Array(matches.dropFirst(start).prefix(size))
        return VODPage(
            items: slice.map(item),
            totalCount: matches.count,
            hasMore: start + slice.count < matches.count
        )
    }

    /// A title by its exact name, for `--demo-vod <title>`.
    static func item(named name: String) -> VODItem? {
        titles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(item)
    }

    private static func item(_ title: DemoVODTitle) -> VODItem {
        VODItem(
            itemId: title.id,
            uuid: title.uuid,
            name: title.name,
            kind: title.kind,
            description: title.plot,
            year: title.year,
            rating: title.rating,
            genre: title.genre,
            durationSecs: title.kind == .movies ? title.minutes * 60 : nil,
            episodeCount: title.kind == .series ? title.seasons.reduce(0) { $0 + $1.count } : nil,
            logo: VODLogo(id: title.id, url: title.poster, cacheURL: title.poster)
        )
    }

    // MARK: - Details

    static func movieDetail(id: Int) -> VODMovieDetail? {
        guard let title = movies.first(where: { $0.id == id }) else { return nil }
        return VODMovieDetail(
            id: title.id,
            uuid: title.uuid,
            name: title.name,
            plot: title.plot,
            year: title.year,
            genre: title.genre,
            director: title.director,
            actors: title.actors,
            country: "Canada",
            rating: title.rating,
            durationSecs: title.minutes * 60,
            cover: title.poster,
            backdrops: [title.backdrop]
        )
    }

    static func seriesDetail(id: Int) -> VODSeriesDetail? {
        guard let title = series.first(where: { $0.id == id }) else { return nil }
        return VODSeriesDetail(
            id: title.id,
            name: title.name,
            description: title.plot,
            year: title.year,
            genre: title.genre,
            rating: title.rating,
            cover: VODLogo(id: title.id, url: title.poster, cacheURL: title.poster),
            backdrops: [title.backdrop],
            episodes: episodes(of: title)
        )
    }

    private static func episodes(of title: DemoVODTitle) -> [VODEpisode] {
        title.seasons.enumerated().flatMap { seasonIndex, season in
            season.enumerated().map { episodeIndex, episode in
                let seasonNumber = seasonIndex + 1
                let episodeNumber = episodeIndex + 1
                return VODEpisode(
                    id: title.id * 1000 + seasonNumber * 100 + episodeNumber,
                    uuid: title.episodeUUID(season: seasonNumber, episode: episodeNumber),
                    name: episode.title,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    description: episode.plot,
                    // One a week, a season a year.
                    airDate: String(
                        format: "%04d-%02d-%02d",
                        title.year + seasonIndex, 1 + episodeIndex / 4, 3 + (episodeIndex % 4) * 7
                    ),
                    // A minute or two either side of the usual runtime.
                    durationSecs: (title.minutes + (episodeIndex * 7 + seasonIndex * 3) % 5 - 2) * 60
                )
            }
        }
    }

    // MARK: - Watch state

    /// What the demo viewer has already watched, so the pages show resume
    /// bars and watched chips. Real positions saved on the device win.
    static let seededProgress: [String: VODProgress] = {
        let seededAt = Date(timeIntervalSince1970: 1_760_000_000)
        func progress(_ position: Int, of duration: Int) -> VODProgress {
            VODProgress(position: position, duration: duration, updatedAt: seededAt)
        }
        var seeded: [String: VODProgress] = [
            // Gave up on the car chase at 38 km/h.
            "demo-movie-5001": progress(2710, of: 107 * 60),
            "demo-movie-5004": progress(201 * 60, of: 201 * 60),
        ]
        guard let quantum = series.first(where: { $0.id == 6001 }) else { return seeded }
        // All of season one, then stopped part-way into season two.
        for episode in 1...quantum.seasons[0].count {
            seeded[quantum.episodeUUID(season: 1, episode: episode)] = progress(52 * 60, of: 52 * 60)
        }
        seeded[quantum.episodeUUID(season: 2, episode: 1)] = progress(52 * 60, of: 52 * 60)
        seeded[quantum.episodeUUID(season: 2, episode: 2)] = progress(1130, of: 52 * 60)
        return seeded
    }()

    // MARK: - Artwork

    /// `named` is a bundle file name such as "demo_vod_thermostats_poster.jpg".
    static func imageURL(named reference: String) -> URL? {
        let file = reference as NSString
        return Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension)
    }
}
