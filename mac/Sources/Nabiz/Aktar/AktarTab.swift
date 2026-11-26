// Panel > Aktar sekmesi: cihaz avatari (ilerleme halkasi), Dosya sec, son aktarimlar. Surukle-birak PanelView'de.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NabizCore

struct AktarTab: View {
    var model = AktarModel.shared
    var phone = PhoneModel.shared

    var body: some View {
        VStack(spacing: 8) {
            device
            if let n = model.notice {
                Text(n).font(.caption).foregroundStyle(Palette.warning)
                    .frame(maxWidth: .infinity).transition(.opacity)
            }
            if !model.records.isEmpty {
                HStack { TileTitle(text: "Son aktarımlar"); Spacer() }.padding(.horizontal, 6).padding(.top, 2)
                VStack(spacing: 0) {
                    ForEach(Array(model.records.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Divider().padding(.leading, 52) }
                        AktarRow(record: r, model: model)
                    }
                }
                .padding(.vertical, 4)
                .glassTile(cornerRadius: Radius.group)
            }
        }
        .animation(Motion.spring, value: model.records.count)
        .animation(.easeOut(duration: 0.2), value: model.notice)
    }

    @ViewBuilder
    private var device: some View {
        if phone.link == .bagli {
            let active = model.records.first { $0.durum == .suruyor }
            VStack(spacing: 10) {
                Button { model.pickFiles() } label: {
                    AktarAvatar(symbol: "smartphone", fraction: active?.oran)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Dosya seç")
                VStack(spacing: 2) {
                    Text(phone.phoneName ?? phone.paired?.name ?? "Telefon").font(.headline).lineLimit(1)
                    Text(status(active)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Button { model.pickFiles() } label: {
                    Text("Dosya seç").font(.callout.weight(.semibold))
                        .padding(.horizontal, 22).padding(.vertical, 7)
                        .background(Palette.selection, in: Capsule())
                        .glassCapsule(interactive: true)
                }
                .buttonStyle(PressableStyle())
                Text("Dosyaları panele sürükleyip bırakabilirsin.").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 12)
            .glassTile(cornerRadius: Radius.group)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("Telefon bağlı değil").font(.headline)
                Text("Telefonda Nabız uygulamasını aç, aynı Wi-Fi ağında olduğundan emin ol.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 12)
            .glassTile(cornerRadius: Radius.group)
        }
    }

    private func status(_ active: AktarKayit?) -> String {
        guard let a = active else { return "Bağlı" }
        let verb = a.yon == .giden ? "Gönderiyor" : "Alıyor"
        return a.hiz > 0 ? "\(verb) · \(AktarFormat.speed(a.hiz))" : verb
    }
}

enum AktarFormat {
    static func speed(_ bytesPerSecond: Double) -> String { "\(Format.bytes(UInt64(max(0, bytesPerSecond))))/sn" }
}

/// 58 pt yuvarlak avatar; gonderirken / alirken cevresinde mavi ilerleme halkasi.
private struct AktarAvatar: View {
    let symbol: String
    let fraction: Double?

    var body: some View {
        ZStack {
            Circle().fill(Palette.fill)
            Image(systemName: symbol).font(.system(size: 24, weight: .regular)).foregroundStyle(.primary)
            Circle().stroke(Palette.track, lineWidth: fraction == nil ? 0 : 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, fraction ?? 0))))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity((fraction ?? 0) > 0.001 ? 1 : 0)
                .animation(Motion.ring, value: fraction)
        }
        .frame(width: 58, height: 58)
        .glassCapsule()
    }
}

private struct AktarRow: View {
    let record: AktarKayit
    let model: AktarModel

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.baslik).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption).foregroundStyle(subtitleColor).lineLimit(1).monospacedDigit()
                if showsBar { bar }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if record.durum == .bitti { model.reveal(record) } }
    }

    @ViewBuilder private var icon: some View {
        if record.dosyalar.count == 1 {
            let ext = (record.dosyalar[0].ad as NSString).pathExtension
            Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)).resizable().scaledToFit()
        } else {
            Image(systemName: "doc.on.doc").font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }

    private var arrow: String { record.yon == .giden ? "↑" : "↓" }

    private var subtitle: String {
        let size = Format.bytes(UInt64(max(0, record.toplam)))
        switch record.durum {
        case .onayBekliyor: return "\(record.cihaz) göndermek istiyor · \(size)"
        case .yanitBekleniyor: return "Telefonun yanıtı bekleniyor · \(size)"
        case .baglaniyor: return "Bağlanıyor · \(size)"
        case .suruyor:
            let rate = record.hiz > 0 ? " · \(AktarFormat.speed(record.hiz))" : ""
            return "\(arrow) \(Format.bytes(UInt64(max(0, record.bayt)))) / \(size)\(rate)"
        case .kesildi: return "Bağlantı koptu, yeniden deneniyor"
        case .bitti: return "Bitti · \(size) · Finder'da göster"
        case .hata(let m): return m
        }
    }

    private var subtitleColor: Color {
        if case .hata = record.durum { return Palette.critical }
        return .secondary
    }

    private var showsBar: Bool { record.durum == .suruyor || record.durum == .kesildi }

    private var bar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(Color.blue).frame(width: g.size.width * record.oran)
                    .animation(Motion.ring, value: record.oran)
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder private var trailing: some View {
        switch record.durum {
        case .onayBekliyor:
            HStack(spacing: 6) {
                Button { model.respond(record.id, accept: false) } label: { chip("Reddet", strong: false) }
                Button { model.respond(record.id, accept: true) } label: { chip("Kabul et", strong: true) }
            }
            .buttonStyle(PressableStyle())
        case .yanitBekleniyor, .baglaniyor, .suruyor, .kesildi:
            Button { model.cancel(record.id) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("İptal")
        case .bitti:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.charging)
        case .hata:
            Button { model.remove(record.id) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Kaldır")
        }
    }

    private func chip(_ text: String, strong: Bool) -> some View {
        Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(strong ? Palette.selection : Color.clear, in: Capsule())
            .glassCapsule(interactive: true)
    }
}
