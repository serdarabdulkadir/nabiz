// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız için sadeleştirildi.
import Foundation

/// Bir sağlayıcıdaki hesap. Her sağlayıcının bir "yerel" hesabı vardır (aracın kendi oturumu: Claude Code, Codex CLI, Cursor
/// uygulaması; id = sağlayıcı adı). Ek hesaplar web girişiyle eklenir (id = UUID; her biri ayrı çerez kutusu).
/// Saklanan alanlar yalnız ad, id, sağlayıcı ve e-posta; token yok.
public struct AIAccount: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let provider: AIProviderID
    public var name: String?
    public var email: String?

    public init(id: String, provider: AIProviderID, name: String? = nil, email: String? = nil) {
        self.id = id; self.provider = provider; self.name = name; self.email = email
    }

    public static func local(_ provider: AIProviderID) -> AIAccount { AIAccount(id: provider.rawValue, provider: provider) }
    public var isLocal: Bool { id == provider.rawValue }
    /// Ek hesabın çerez kutusu kimliği (yerelde yok: varsayılan kutu).
    public var storeID: UUID? { isLocal ? nil : UUID(uuidString: id) }
    /// Ek hesapta limit kimliği öneki (bildirim / geçmiş anahtarları ayrışsın).
    public var limitPrefix: String { isLocal ? "" : "\(id)." }

    public var customName: String? {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return name
    }
}

public enum AIAccountList {
    /// Yerel hesaplar (sağlayıcı sırasıyla) başta, ardından ek hesaplar (kayıt sırasıyla). Kayıtlı ad/e-posta yerele işlenir.
    public static func merged(saved: [AIAccount]) -> [AIAccount] {
        let locals = AIProviderID.allCases.map { p in saved.first { $0.id == p.rawValue && $0.provider == p } ?? .local(p) }
        return locals + saved.filter { !$0.isLocal }
    }

    /// Diske yazılacak olanlar: ek hesaplar ile adı/e-postası olan yerel hesaplar.
    public static func persisted(_ all: [AIAccount]) -> [AIAccount] {
        all.filter { !$0.isLocal || $0.customName != nil || $0.email != nil }
    }

    public static func accounts(for provider: AIProviderID, in all: [AIAccount]) -> [AIAccount] { all.filter { $0.provider == provider } }

    /// Kartta görünen hesaplar: ek hesap varken verisi olmayan yerel hesap gizlenir (Claude Code yok, yalnız web hesapları var).
    public static func visible(_ provider: AIProviderID, in all: [AIAccount], hasData: (AIAccount) -> Bool) -> [AIAccount] {
        let list = accounts(for: provider, in: all)
        guard list.count > 1, !hasData(list[0]), list.dropFirst().contains(where: hasData) else { return list }
        return Array(list.dropFirst())
    }

    /// Verilen ad ya da sıra numarası ("Hesap 2").
    public static func label(_ account: AIAccount, in all: [AIAccount]) -> String {
        account.customName ?? "Hesap \((accounts(for: account.provider, in: all).firstIndex { $0.id == account.id } ?? 0) + 1)"
    }

    /// Kart / bildirim başlığı: tek hesapta "Claude", birden çoğunda "Claude · İş" / "Claude · Hesap 2".
    public static func title(_ account: AIAccount, in all: [AIAccount]) -> String {
        accounts(for: account.provider, in: all).count > 1 ? "\(account.provider.name) · \(label(account, in: all))" : account.provider.name
    }

    /// Aynı e-posta aynı sağlayıcıda iki kez eklenemez (yerel oturumun e-postası dahil).
    public static func isDuplicate(email: String, provider: AIProviderID, in all: [AIAccount], localEmail: String?) -> Bool {
        let e = email.lowercased()
        return accounts(for: provider, in: all).contains { $0.email?.lowercased() == e } || localEmail?.lowercased() == e
    }

    /// Ek hesapta limit kimlikleri "<uuid>." önekli.
    public static func prefixed(_ limits: [AILimit], for account: AIAccount) -> [AILimit] {
        guard !account.isLocal else { return limits }
        return limits.map { var l = $0; l.id = account.limitPrefix + l.id; return l }
    }
}
