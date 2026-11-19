import Testing
import Foundation
@testable import NabizCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func claudeYanitiAyristirilir() throws {
    let json = """
    {"five_hour":{"utilization":42,"resets_at":"2027-01-15T10:00:00Z"},"seven_day":null,
     "seven_day_opus":{"utilization":12.5,"resets_at":null},"harbor_lantern":{"utilization":3,"limit_dollars":100},
     "iguana":null,"extra_usage":{"utilization":5}}
    """
    let l = AIParse.claude(Data(json.utf8))
    #expect(l.map(\.id).prefix(2) == ["claude.five_hour", "claude.seven_day"])
    #expect(l[0].label == "5 saat" && l[0].used == 42 && l[0].window == 18_000 && l[0].model == nil)
    #expect(l[1].used == 0)                                   // null ana pencere = %0
    let opus = try #require(l.first { $0.id == "claude.seven_day_opus" })
    #expect(opus.model == "opus" && opus.label == "Haftalık · Opus")
    #expect(l.first { $0.id == "claude.harbor_lantern" }?.label == "Ek kota")
    #expect(l.first { $0.id == "claude.harbor_lantern" }?.model == AILimit.unnamed)
    #expect(l.first { $0.id == "claude.iguana" } == nil)
    #expect(AIParse.claude(Data("%%".utf8)).isEmpty)
}

@Test func codexVeCursorYanitiAyristirilir() throws {
    let codex = try #require(try JSONSerialization.jsonObject(with: Data("""
    {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":30,"limit_window_seconds":18000,"reset_at":1800003600},
     "secondary_window":{"used_percent":55,"limit_window_seconds":604800,"reset_at":1800500000}},
     "code_review_rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":604800}}}
    """.utf8)) as? [String: Any])
    let c = AIParse.codex(codex)
    #expect(c.plan == "Plus" && c.limits.count == 3)
    #expect(c.limits[0].label == "5 saat" && c.limits[0].model == nil)
    #expect(c.limits.last?.model == "review" && c.limits.last?.label == "Review, Haftalık")

    let cursor = try #require(try JSONSerialization.jsonObject(with: Data("""
    {"membershipType":"pro_plus","billingCycleStart":"2027-01-01T00:00:00.000Z","billingCycleEnd":"2027-01-31T00:00:00.000Z",
     "individualUsage":{"plan":{"used":1560,"limit":2000,"totalPercentUsed":78,"autoPercentUsed":10,"apiPercentUsed":90}}}
    """.utf8)) as? [String: Any])
    let u = AIParse.cursor(cursor)
    #expect(u.plan == "Pro Plus" && u.limits.map(\.id) == ["cursor.plan", "cursor.auto", "cursor.api"])
    #expect(u.limits[0].used == 78 && u.limits[0].window == 30 * 86_400)
    #expect(u.note?.contains("15,60") == true)
}

@Test func sifirlananLimitSifirGosterilirVeTukenmeOngoru() {
    let l = AILimit(id: "a", label: "5 saat", percent: 88, resetsAt: now.addingTimeInterval(-1), window: 18_000)
    #expect(l.percent(at: now) == 0 && l.didReset(at: now))
    // Pencerenin yarısında %60: hız ile ~ 20 dk'da dolar, kalan 2,5 sa'in %90'ından erken -> değer döner
    let fast = AILimit(id: "b", label: "5 saat", percent: 60, resetsAt: now.addingTimeInterval(9_000), window: 18_000)
    let t = fast.timeToFull(at: now)
    #expect(t != nil && abs(t! - 6_000) < 1)
    // Tam tempo (yüzde 50, yarıda): erken dolmaz
    #expect(AILimit(id: "c", label: "x", percent: 50, resetsAt: now.addingTimeInterval(9_000), window: 18_000).timeToFull(at: now) == nil)
    // Pencerenin ilk %5'inde veri yetersiz
    #expect(AILimit(id: "d", label: "x", percent: 10, resetsAt: now.addingTimeInterval(17_900), window: 18_000).timeToFull(at: now) == nil)
}

@Test func onLimitlerKisaPencereVeGenelSecilir() {
    let five = AILimit(id: "five", label: "5 saat", percent: 20, resetsAt: nil, window: 18_000)
    let week = AILimit(id: "week", label: "Haftalık", percent: 50, resetsAt: nil, window: 604_800)
    let opus = AILimit(id: "opus", label: "Haftalık · Opus", percent: 70, resetsAt: nil, window: 604_800, model: "opus")
    var h = AIUsageHistory()
    h.record([opus], at: now)
    h.record([AILimit(id: "opus", label: "x", percent: 75, resetsAt: nil, window: nil, model: "opus")], at: now.addingTimeInterval(1))
    #expect(AIFront.limits([five, week, opus], history: h, at: now).map(\.id) == ["five", "opus"])   // opus son artan ve daha dolu
    #expect(AIFront.limits([five, week], history: AIUsageHistory(), at: now).map(\.id) == ["five", "week"])
    // %90'ı geçen gizli sayaç öne zorlanır
    let hidden = AILimit(id: "h", label: "Diğer", percent: 95, resetsAt: nil, window: nil, model: AILimit.unnamed)
    #expect(AIFront.limits([five, week, hidden], history: AIUsageHistory(), at: now).map(\.id) == ["five", "h"])
    #expect(AIFront.limits([], history: AIUsageHistory(), at: now).isEmpty)
}

@Test func yenilemeTakvimiVeBekleme() {
    #expect(AIRefreshPolicy.shouldRefreshOnOpen(lastRefresh: now.addingTimeInterval(-61), now: now))
    #expect(!AIRefreshPolicy.shouldRefreshOnOpen(lastRefresh: now.addingTimeInterval(-30), now: now))
    #expect(AIRefreshPolicy.isDue(lastRefresh: now.addingTimeInterval(-300), busy: false, now: now))
    #expect(!AIRefreshPolicy.isDue(lastRefresh: now.addingTimeInterval(-100), busy: false, now: now))
    #expect(AIRefreshPolicy.isDue(lastRefresh: now.addingTimeInterval(-60), busy: true, now: now))
    var u = AIProviderUsage()
    u.limits = [AILimit(id: "a", label: "x", percent: 80, resetsAt: now.addingTimeInterval(100), window: nil)]
    #expect(AIRefreshPolicy.isBusy([u], at: now))
    #expect(AIRefreshPolicy.nextBackoff(after: nil) == 300 && AIRefreshPolicy.nextBackoff(after: 1200) == 1800)
    #expect(AIRefreshPolicy.minGap(.claude) == 180 && AIRefreshPolicy.minGap(.codex) == 20)
}

@Test func esikBildirimiPencereBasinaBirKez() {
    let reset = now.addingTimeInterval(7200)
    var o = AIThreshold.evaluate(percent: 76, resetsAt: reset, saved: nil)
    #expect(o.notify == 75)
    o = AIThreshold.evaluate(percent: 80, resetsAt: reset.addingTimeInterval(30), saved: o.record)   // anı kayması: aynı pencere
    #expect(o.notify == 0)
    o = AIThreshold.evaluate(percent: 91, resetsAt: reset, saved: o.record)
    #expect(o.notify == 90)
    o = AIThreshold.evaluate(percent: 92, resetsAt: reset, saved: o.record)
    #expect(o.notify == 0)
    // Yeni pencere (anı 5 sa ileride): yeniden bildirilir
    o = AIThreshold.evaluate(percent: 80, resetsAt: reset.addingTimeInterval(18_000), saved: o.record)
    #expect(o.notify == 75)
    #expect(AIThreshold.evaluate(percent: 10, resetsAt: reset, saved: nil).notify == 0)
}

@Test func ipucuVeTelBicimi() throws {
    #expect(AIIssue.from(.needsLogin, provider: .claude).action == .login)
    #expect(AIIssue.from(.needsLogin, provider: .cursor, cursorInstalled: true).action == .openApp("Cursor"))
    #expect(AIIssue.from(.needsPermission, provider: .claude).actionTitle == "İzin ver")
    #expect(AIIssue.from(.http(500), provider: .codex).actionTitle == "Tekrar dene")

    var u = AIProviderUsage()
    u.plan = "Max"; u.updatedAt = now
    u.limits = [AILimit(id: "claude.five_hour", label: "5 saat", percent: 42.4, resetsAt: now.addingTimeInterval(10_000), window: 18_000),
                AILimit(id: "claude.opus", label: "Opus", percent: 12, resetsAt: nil, window: nil, model: "opus")]
    let w = AIWireProvider(provider: .claude, usage: u, at: now)
    #expect(w.id == "claude" && w.ad == "Claude" && w.plan == "Max" && w.guncel == 1_800_000_000)
    #expect(w.limitler[0].yuzde == 42 && w.limitler[0].genel && w.limitler[0].sifirlanma == 1_800_010_000)
    #expect(w.limitler[1].genel == false && w.limitler[1].sifirlanma == nil)
    let msg = PeerEnvelope(.aiState([w]))
    #expect(try PeerCodec.decode(try PeerCodec.encode(msg)) == msg)
    #expect(AIText.countdown(3 * 86_400 + 7200) == "3 g 2 sa" && AIText.within(7300) == "2 saatte" && AIText.short(90) == "1 dk")
}

@Test func hesapListesiVeAdlandirma() {
    let work = AIAccount(id: "5B1E0C3A-7D2F-4E21-9A6B-1C2D3E4F5A6B", provider: .claude, name: "İş", email: "Is@x.com")
    let second = AIAccount(id: "6B1E0C3A-7D2F-4E21-9A6B-1C2D3E4F5A6B", provider: .claude)
    let all = AIAccountList.merged(saved: [work, second])
    #expect(all.map(\.id).prefix(3) == ["claude", "codex", "cursor"] && all.count == 5)       // yerel önce
    #expect(AIAccountList.title(work, in: all) == "Claude · İş")
    #expect(AIAccountList.title(second, in: all) == "Claude · Hesap 3")
    #expect(AIAccountList.title(.local(.codex), in: all) == "Codex")                           // tek hesapta ad yok
    #expect(AIAccountList.persisted(all).map(\.id) == [work.id, second.id])
    #expect(AIAccountList.isDuplicate(email: "is@X.com", provider: .claude, in: all, localEmail: nil))
    #expect(AIAccountList.isDuplicate(email: "me@x.com", provider: .codex, in: all, localEmail: "ME@x.com"))
    #expect(!AIAccountList.isDuplicate(email: "is@x.com", provider: .codex, in: all, localEmail: nil))
    // Yerel verisi yokken ek hesaplar varsa yerel gizlenir
    let vis = AIAccountList.visible(.claude, in: all) { $0.id != "claude" }
    #expect(vis.map(\.id) == [work.id, second.id])
    #expect(AIAccountList.visible(.claude, in: all) { _ in false }.count == 3)
    let l = AILimit(id: "claude.five_hour", label: "5 saat", percent: 1, resetsAt: nil, window: nil)
    #expect(AIAccountList.prefixed([l], for: work)[0].id == work.id + ".claude.five_hour")
    #expect(AIAccountList.prefixed([l], for: .local(.claude))[0].id == "claude.five_hour")
    #expect(work.storeID != nil && AIAccount.local(.codex).storeID == nil)
    let wire = AIWireProvider(provider: .claude, accountId: work.id, accountName: "İş", usage: AIProviderUsage())
    #expect(wire.hesapId == work.id && wire.hesap == "İş")
    #expect(AIWireProvider(provider: .codex, usage: AIProviderUsage()).hesapId == "codex")
}

@Test func limitSeviyesiTempoyaBakar() {
    let calm = AILimit(id: "a", label: "x", percent: 30, resetsAt: now.addingTimeInterval(9_000), window: 18_000)   // yarıda %30
    #expect(calm.level(at: now) == 0)
    let fast = AILimit(id: "b", label: "x", percent: 62, resetsAt: now.addingTimeInterval(9_000), window: 18_000)   // yarıda %62: tempodan hızlı
    #expect(fast.level(at: now) == 1)
    #expect(AILimit(id: "c", label: "x", percent: 91, resetsAt: nil, window: nil).level(at: now) == 2)
    #expect(AILimit(id: "d", label: "x", percent: 80, resetsAt: nil, window: nil).level(at: now) == 1)
}
