import Testing
@testable import SlowVapeCore

private func countedFrames(_ samples: [(PuffCounter.Signal, Double)]) -> [Double] {
    var counter = PuffCounter()
    return samples.compactMap { signal, time in
        counter.update(signal, at: time) ? time : nil
    }
}

@Test func countsOneGestureAcrossManyFramesAndAllowsTheNext() {
    let counts = countedFrames([
        (.away, 0), (.near, 0.1), (.near, 0.2), (.near, 0.3), (.near, 0.4),
        (.near, 0.5), (.near, 0.6), (.away, 0.7), (.away, 0.85), (.away, 0.95),
        (.near, 1.05), (.near, 1.2), (.near, 1.35), (.near, 1.51),
        (.away, 1.6), (.away, 1.75)
    ])
    #expect(counts == [0.85, 1.75])
}

@Test func startupNearMouthAndBriefPassDoNotCount() {
    let counts = countedFrames([
        (.near, 0), (.near, 0.15), (.near, 0.3), (.near, 0.45),
        (.away, 0.55), (.near, 0.65), (.away, 0.75), (.away, 0.9)
    ])
    #expect(counts.isEmpty)
}

@Test func toleratesBriefOcclusionButDoesNotCountACameraGap() {
    let counts = countedFrames([
        (.away, 0), (.near, 0.1), (.near, 0.25), (.uncertain, 0.35),
        (.near, 0.45), (.near, 0.6), (.away, 0.7), (.away, 0.85),
        (.near, 1.0), (.near, 1.15), (.near, 1.3), (.near, 1.45),
        (.uncertain, 1.55), (.uncertain, 1.95), (.away, 2.0), (.away, 2.15)
    ])
    #expect(counts == [0.85])
}

@Test func supportsTheVapeLeavingTheFrameWithFaceStillVisible() {
    let counts = countedFrames([
        (.absent, 0), (.near, 0.1), (.near, 0.25), (.near, 0.4), (.near, 0.55),
        (.absent, 0.65), (.absent, 0.8), (.absent, 0.95), (.absent, 1.1),
        (.absent, 1.25), (.near, 1.35), (.near, 1.5), (.absent, 1.65)
    ])
    #expect(counts == [1.25])
}

@Test func intermittentDetectionAtTheLipsStillCountsOnWithdrawal() {
    let counts = countedFrames([
        (.away, 0), (.near, 0.1), (.absent, 0.2), (.near, 0.3),
        (.absent, 0.4), (.near, 0.5), (.away, 0.6), (.away, 0.75),
        (.away, 0.9)
    ])
    #expect(counts == [0.75])
}

@Test func aSingleGlimpseFollowedByDisappearanceDoesNotCount() {
    let counts = countedFrames([
        (.away, 0), (.near, 0.1), (.absent, 0.2), (.absent, 0.35),
        (.absent, 0.5), (.absent, 0.65), (.absent, 0.8), (.absent, 0.95)
    ])
    #expect(counts.isEmpty)
}
