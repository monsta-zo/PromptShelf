import SwiftUI
import Speech

struct PromptHistoryView: View {

    @EnvironmentObject var history: PromptHistory
    @State private var copiedID: UUID?
    @AppStorage("speechLocale")    private var speechLocale: String = "en-US"
    @AppStorage("addedLocales")    private var addedLocalesRaw: String = "en-US"
    @State private var showingLanguagePicker = false
    @State private var showingHowTo = false

    // Comma-separated storage → array
    private var addedLocales: [String] {
        addedLocalesRaw.components(separatedBy: ",").filter { !$0.isEmpty }
    }
    private func saveLocales(_ locales: [String]) {
        addedLocalesRaw = locales.joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if history.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
            Divider()
            languagePicker
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Prompt History")
                .font(.headline)
            Spacer()
            if !history.entries.isEmpty {
                Button("Clear All") { history.clear() }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
            }
            Button {
                showingHowTo = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingHowTo) {
                HowToView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - List

    private var entryList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(history.entries) { entry in
                    entryRow(entry)
                    Divider().padding(.leading, 14)
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private func entryRow(_ entry: PromptEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundColor(.primary)

                Text(entry.date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
                copiedID = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if copiedID == entry.id { copiedID = nil }
                }
            } label: {
                Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(copiedID == entry.id ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                history.remove(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Language Picker

    private var languagePicker: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Language")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Added language toggle buttons
            HStack(spacing: 0) {
                ForEach(addedLocales, id: \.self) { locale in
                    langButton(label: shortLabel(for: locale), locale: locale)
                }
            }
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            // Add language button
            Button {
                showingLanguagePicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingLanguagePicker, arrowEdge: .bottom) {
                LanguagePickerPopover(
                    addedLocales: addedLocales,
                    currentLocale: speechLocale,
                    onToggle: { locale in
                        var list = addedLocales
                        if list.contains(locale) {
                            // Don't remove if it's the only one or currently selected
                            guard list.count > 1 else { return }
                            list.removeAll { $0 == locale }
                            if speechLocale == locale {
                                speechLocale = list.first ?? "en-US"
                            }
                        } else {
                            list.append(locale)
                        }
                        saveLocales(list)
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func langButton(label: String, locale: String) -> some View {
        Button {
            speechLocale = locale
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(speechLocale == locale ? Color.accentColor : Color.clear)
                .foregroundStyle(speechLocale == locale ? Color.white : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// Short display label for a locale identifier
    private func shortLabel(for identifier: String) -> String {
        let map: [String: String] = [
            "en-US": "EN", "en-GB": "EN", "en-AU": "EN", "en-CA": "EN",
            "ko-KR": "한",
            "ja-JP": "日",
            "zh-CN": "中", "zh-TW": "繁", "zh-HK": "粵",
            "fr-FR": "FR", "fr-CA": "FR", "fr-CH": "FR", "fr-BE": "FR",
            "de-DE": "DE", "de-AT": "DE", "de-CH": "DE",
            "es-ES": "ES", "es-MX": "ES", "es-US": "ES", "es-419": "ES",
            "pt-BR": "PT", "pt-PT": "PT",
            "ru-RU": "RU",
            "ar-SA": "ع",
            "hi-IN": "हि",
            "it-IT": "IT", "it-CH": "IT",
            "nl-NL": "NL", "nl-BE": "NL",
            "pl-PL": "PL",
            "tr-TR": "TR",
            "sv-SE": "SV",
            "da-DK": "DA",
            "nb-NO": "NO",
            "fi-FI": "FI",
            "cs-CZ": "CS",
            "sk-SK": "SK",
            "ro-RO": "RO",
            "hu-HU": "HU",
            "el-GR": "EL",
            "uk-UA": "UK",
            "th-TH": "ไท",
            "vi-VN": "VI",
            "id-ID": "ID",
            "ms-MY": "MS",
            "he-IL": "עב",
            "ca-ES": "CA",
            "hr-HR": "HR",
        ]
        if let label = map[identifier] { return label }
        // Fallback: uppercase language code
        return identifier.components(separatedBy: "-").first?.uppercased() ?? identifier
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No prompts yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Quick shortcut reference
            VStack(spacing: 0) {
                shortcutRow(keys: "⌃ + ⌥", label: "Start / cancel session")
                Divider().padding(.leading, 14)
                shortcutRow(keys: "⌘ + C", label: "Capture text or image")
                Divider().padding(.leading, 14)
                shortcutRow(keys: "⌘ + ⇧ + 4", label: "Screenshot to shelf")
                Divider().padding(.leading, 14)
                shortcutRow(keys: "⌘ + V", label: "Paste everything in order")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func shortcutRow(keys: String, label: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 88, alignment: .leading)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Language Picker Popover

struct LanguagePickerPopover: View {

    let addedLocales: [String]
    let currentLocale: String
    let onToggle: (String) -> Void

    @State private var searchText = ""

    private static let allLocales: [String] = SFSpeechRecognizer.supportedLocales()
        .map { $0.identifier }
        .sorted { Self.displayName($0) < Self.displayName($1) }

    private var filtered: [String] {
        guard !searchText.isEmpty else { return Self.allLocales }
        return Self.allLocales.filter {
            displayName($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Languages")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Language list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.self) { locale in
                        localeRow(locale)
                    }
                }
            }
            .frame(height: 280)
        }
        .frame(width: 270)
    }

    @ViewBuilder
    private func localeRow(_ locale: String) -> some View {
        let isAdded  = addedLocales.contains(locale)
        let isCurrent = currentLocale == locale
        let isLast   = addedLocales.count == 1 && isAdded

        Button { onToggle(locale) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName(locale))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary)
                    Text(locale)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Text("active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                } else if isAdded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(isLast ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isLast)

        Divider().padding(.leading, 14)
    }

    private static func displayName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private func displayName(_ identifier: String) -> String {
        Self.displayName(identifier)
    }
}
