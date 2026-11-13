import SwiftUI
import SwiftData

struct VaultView: View {
    @Environment(TokenWallet.self) private var wallet
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", unlocked = "Unlocked"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var day: Date?
    @State private var showCalendar = false
    @FocusState private var searching: Bool

    @State private var revealing: Entry?
    @State private var deleting: Entry?
    @State private var earlyCandidate: Entry?
    @State private var deleteCandidate: Entry?
    @State private var noTokens: Entry?
    @State private var revealed = 0
    @State private var denied = 0
    @State private var refunded = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            let matching = entries.filter { matches($0) }
            let locked = matching.filter { !$0.isReady(at: now) || $0.isPendingDeletion }
                .sorted { $0.opensAt == $1.opensAt ? $0.createdAt > $1.createdAt : $0.opensAt < $1.opensAt }
            let open = matching.filter { $0.isReady(at: now) && !$0.isPendingDeletion }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Picker("Show", selection: $filter.animation(.snappy)) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    SearchField(text: $query, focused: $searching)

                    WeekStrip(entries: entries, now: now, selected: $day)

                    if let day { dayChip(day) }

                    if entries.isEmpty {
                        emptyState
                    } else if matching.isEmpty || (filter == .unlocked && open.isEmpty) {
                        noResults
                    } else {
                        if filter == .all && !locked.isEmpty {
                            section("Resting", count: locked.count, list: locked, now: now)
                        }
                        if !open.isEmpty {
                            section("Unlocked", count: open.count, list: open, now: now)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: open.count) { old, new in
                // An entry just reached its day: hand back any token spent on it.
                if new > old, VaultCare.refundMatured(entries, context: context, now: now) > 0 { refunded += 1 }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: revealed)
        .sensoryFeedback(.warning, trigger: denied)
        .sensoryFeedback(.success, trigger: refunded)
        .sensoryFeedback(.selection, trigger: day)
        .fullScreenCover(item: $revealing) { RevealView(entry: $0) }
        .sheet(isPresented: $showCalendar) {
            VaultCalendar(entries: entries, selected: $day)
        }
        .alert("Still resting", isPresented: Binding(
            get: { noTokens != nil }, set: { if !$0 { noTokens = nil } }), presenting: noTokens) { _ in
            Button("OK", role: .cancel) {}
        } message: { entry in
            Text("It opens \(Fmt.longDate(entry.opensAt)). Early reveals refill next week.")
        }
        .sheet(item: $deleting) { DeleteView(entry: $0) }
        .alert("Open this entry early?", isPresented: Binding(
            get: { earlyCandidate != nil }, set: { if !$0 { earlyCandidate = nil } }),
            presenting: earlyCandidate) { entry in
            Button("Not Now", role: .cancel) {}
            Button("Open") {
                guard wallet.spend() else { return }
                entry.revealedEarlyAt = .now
                try? context.save()
                revealed += 1
                revealing = entry
            }
            .keyboardShortcut(.defaultAction)
        } message: { entry in
            Text("Uses 1 of your \(wallet.available()) early reveals. It stays open from now on, and the token comes back on \(Fmt.longDate(entry.opensAt)) when it would have opened anyway.")
        }
        .alert("Delete this entry?", isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            presenting: deleteCandidate) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                entry.deletionRequestedAt = .now
                deleting = entry
            }
        } message: { _ in
            Text("You'll confirm once more in 2 hours. You can change your mind until then.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vault")
                    .font(.system(size: 34, weight: .semibold))
                    .kerning(-1.2)
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button { showCalendar = true } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .glass(22)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Browse by date")
            .padding(.top, 2)
        }
    }

    private func section(_ title: String, count: Int, list: [Entry], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).sectionLabel()
                Spacer()
                Text("\(count)").sectionLabel().monospacedDigit()
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            LazyVStack(spacing: 10) {
                ForEach(list) { entry in
                    Button { tap(entry, now: now) } label: {
                        EntryCard(entry: entry, now: now)
                    }
                    .buttonStyle(PressableCardStyle())
                    .contextMenu { menu(for: entry, now: now) }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                            removal: .opacity.combined(with: .scale(scale: 0.96))))
                }
            }
            .animation(.snappy, value: list.map(\.id))
        }
    }

    private func dayChip(_ day: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").font(.footnote.weight(.semibold))
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .font(.footnote.weight(.semibold))
            Button {
                withAnimation(.snappy) { self.day = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.tertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show all days")
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .background(Theme.accent.opacity(0.16), in: Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var subtitle: String {
        let n = entries.count
        let resting = entries.filter { !$0.isReady() }.count
        if n == 0 { return "Nothing resting yet" }
        return "\(n) \(n == 1 ? "entry" : "entries") · \(resting) resting"
    }

    private func matches(_ entry: Entry) -> Bool {
        if let day, !Calendar.current.isDate(entry.createdAt, inSameDayAs: day) { return false }
        return VaultSearch.matches(entry.createdAt, query: query)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing resting yet", systemImage: "moon.stars")
        } description: {
            Text("What you seal on Today appears here, out of reach for \(Entry.sealDays) days.")
        }
        .foregroundStyle(Theme.ink)
        .padding(.top, 30)
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label(filter == .unlocked && query.isEmpty && day == nil ? "Nothing unlocked yet" : "No entries found",
                  systemImage: filter == .unlocked && query.isEmpty && day == nil ? "lock" : "magnifyingglass")
        } description: {
            Text(filter == .unlocked && query.isEmpty && day == nil
                 ? "Entries unlock at midnight, \(Entry.sealDays) days after you write them."
                 : "Try a day like “Nov 3”, a weekday, or a time like “9 pm”.")
        }
        .foregroundStyle(Theme.ink)
        .padding(.top, 30)
    }

    private func tap(_ entry: Entry, now: Date) {
        searching = false
        if entry.isPendingDeletion { deleting = entry }
        else if entry.isReady(at: now) { revealing = entry }
        else if wallet.available(at: now) > 0 { earlyCandidate = entry }
        else { denied += 1; noTokens = entry }
    }

    @ViewBuilder
    private func menu(for entry: Entry, now: Date) -> some View {
        if entry.isPendingDeletion {
            Button("View deletion", systemImage: "clock") { deleting = entry }
            Button("Cancel deletion", systemImage: "arrow.uturn.backward") { entry.deletionRequestedAt = nil }
        } else {
            if entry.isReady(at: now) {
                Button("Reveal for 60 seconds", systemImage: "eye") { revealing = entry }
            } else if wallet.available(at: now) > 0 {
                Button("Reveal early · 1 token", systemImage: "eye") { earlyCandidate = entry }
            }
            Button("Show this day", systemImage: "calendar") {
                withAnimation(.snappy) { day = Calendar.current.startOfDay(for: entry.createdAt) }
            }
            Button("Delete…", systemImage: "trash", role: .destructive) { deleteCandidate = entry }
        }
    }
}

/// Matches a date against what people type: "nov 3", "tuesday", "9 pm", "21:40", "11/3", "2026", "morning".
enum VaultSearch {
    static func tokens(for date: Date) -> Set<String> {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let hour = c.hour ?? 0, minute = c.minute ?? 0, month = c.month ?? 1, day = c.day ?? 1
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "am" : "pm"
        let mm = String(format: "%02d", minute)
        var t: Set<String> = [
            date.formatted(.dateTime.weekday(.wide)).lowercased(),
            date.formatted(.dateTime.weekday(.abbreviated)).lowercased(),
            date.formatted(.dateTime.month(.wide)).lowercased(),
            date.formatted(.dateTime.month(.abbreviated)).lowercased(),
            "\(day)", "\(c.year ?? 0)", "\(month)/\(day)", "\(day)/\(month)",
            "\(month)/\(day)/\(c.year ?? 0)",
            "\(h12)", "\(h12)\(ampm)", "\(h12):\(mm)", "\(h12):\(mm)\(ampm)", ampm,
            "\(hour):\(mm)", String(format: "%02d:%@", hour, mm),
            Fmt.period(date).lowercased()
        ]
        if cal.isDateInToday(date) { t.insert("today") }
        if cal.isDateInYesterday(date) { t.insert("yesterday") }
        return t
    }

    static func matches(_ date: Date, query: String) -> Bool {
        var q = query.lowercased().replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        // "9 pm" → "9pm", "9:30 am" → "9:30am"
        q = q.replacingOccurrences(of: #"(\d)\s+(am|pm)"#, with: "$1$2", options: .regularExpression)
        // "1st", "22nd" → "1", "22"
        q = q.replacingOccurrences(of: #"(\d+)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        let words = q.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let tokens = tokens(for: date)
        return words.allSatisfy { word in
            if word.first?.isNumber == true { return tokens.contains(word) }
            return tokens.contains { $0.hasPrefix(word) }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                TextField("Search by date or time", text: $text)
                    .focused(focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(Theme.ink)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.tertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(height: 38)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            if focused.wrappedValue {
                Button("Cancel") {
                    text = ""
                    focused.wrappedValue = false
                }
                .foregroundStyle(Theme.accent)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: focused.wrappedValue)
    }
}

private struct WeekStrip: View {
    let entries: [Entry]
    let now: Date
    @Binding var selected: Date?

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0 - 6, to: today) }
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let isSelected = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
                let isToday = cal.isDate(day, inSameDayAs: today)
                let has = entries.contains { cal.isDate($0.createdAt, inSameDayAs: day) }
                Button {
                    withAnimation(.snappy) { selected = isSelected ? nil : day }
                } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.7)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 16, weight: .semibold))
                        Circle()
                            .fill(has ? (isSelected ? Color.black : Theme.accent) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(isSelected ? Color.black : (isToday ? Theme.accent : Theme.ink))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(isSelected ? Theme.ink : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (has ? ", has an entry" : ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(8)
        .card(20)
    }
}

/// Month grid for browsing the vault by date. Days with entries get a dot.
private struct VaultCalendar: View {
    let entries: [Entry]
    @Binding var selected: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var month: Date = Calendar.current.startOfDay(for: .now)

    private let cal = Calendar.current
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: 7) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Button { shift(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .disabled(!canGoBack)
                    .accessibilityLabel("Previous month")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Spacer()
                    Button { shift(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .disabled(!canGoForward)
                    .accessibilityLabel("Next month")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day { dayCell(day) } else { Color.clear.frame(height: 44) }
                    }
                }
                .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                    if value.translation.width < -50, canGoForward { shift(1) }
                    if value.translation.width > 50, canGoBack { shift(-1) }
                })

                Text(monthSummary)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Browse by date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selected != nil {
                        Button("Show All") { selected = nil; dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
        .presentationDragIndicator(.visible)
        .onAppear {
            let start = selected ?? entries.first?.createdAt ?? .now
            month = cal.dateInterval(of: .month, for: start)?.start ?? start
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var cells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let lead = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: lead) + days
    }

    private var entryDays: [Date: Int] {
        Dictionary(grouping: entries) { cal.startOfDay(for: $0.createdAt) }.mapValues(\.count)
    }

    private var oldestMonth: Date {
        let oldest = entries.last?.createdAt ?? .now
        return cal.dateInterval(of: .month, for: oldest)?.start ?? oldest
    }

    private var canGoBack: Bool { month > oldestMonth }
    private var canGoForward: Bool { month < (cal.dateInterval(of: .month, for: .now)?.start ?? .now) }

    private var monthSummary: String {
        let n = entries.filter { cal.isDate($0.createdAt, equalTo: month, toGranularity: .month) }.count
        return n == 0 ? "No entries this month" : "\(n) \(n == 1 ? "entry" : "entries") this month"
    }

    private func shift(_ delta: Int) {
        guard let next = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.snappy) { month = next }
    }

    private func dayCell(_ day: Date) -> some View {
        let count = entryDays[cal.startOfDay(for: day)] ?? 0
        let isSelected = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let isToday = cal.isDateInToday(day)
        return Button {
            selected = cal.startOfDay(for: day)
            dismiss()
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: count > 0 || isToday ? .semibold : .regular))
                Circle()
                    .fill(count > 0 ? (isSelected ? Color.black : Theme.accent) : .clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isSelected ? Color.black : count > 0 ? Theme.ink : (isToday ? Theme.accent : Theme.tertiary))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? Theme.ink : (isToday ? Color.white.opacity(0.06) : .clear),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted)
                            + (count > 0 ? ", \(count) \(count == 1 ? "entry" : "entries")" : ", no entries"))
    }
}

private struct EntryCard: View {
    let entry: Entry
    let now: Date

    private var ready: Bool { entry.isReady(at: now) && !entry.isPendingDeletion }

    private var placeholder: String {
        // AES-GCM adds 28 bytes (nonce + tag) to the plaintext.
        let length = min(140, max(24, entry.cipher.count - 28))
        let words = ["quiet", "today", "felt", "the", "and", "morning", "something", "I", "was", "light", "still", "about"]
        var out = ""
        var i = Int(entry.id.uuid.0)
        while out.count < length { out += words[i % words.count] + " "; i += 7 }
        return String(out.prefix(length))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(Fmt.time(entry.createdAt))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
                status
            }
            // Never decrypt for the list: the preview is blurred anyway, so a
            // placeholder of similar length looks the same and keeps scrolling smooth.
            Text(placeholder)
                .font(.system(size: 15))
                .lineLimit(2)
                .foregroundStyle(ready ? Theme.ink.opacity(0.75) : Theme.secondary)
                .blur(radius: 7)
                .privacySensitive()
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        .padding(16)
        .background(ready ? Color(white: 0.09) : Theme.card,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(ready ? Theme.accent.opacity(0.35) : Theme.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Fmt.exact(entry.createdAt))
    }

    @ViewBuilder private var status: some View {
        if let confirmAt = entry.deletionConfirmableAt {
            Text(confirmAt > now ? "Deleting · \(Fmt.hm(confirmAt.timeIntervalSince(now)))" : "Ready to delete")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        } else if ready {
            Label("Ready", systemImage: "lock.open.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accent.opacity(0.18), in: Capsule())
                .foregroundStyle(Theme.accent)
        } else {
            Label(Fmt.opensIn(entry.opensAt.timeIntervalSince(now)), systemImage: "lock.fill")
                .font(.footnote)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var footer: some View {
        if ready {
            HStack {
                Label("Reveal for 60 seconds", systemImage: "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if entry.wasOpenedEarly {
                    Text("Opened early")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            }
        } else if entry.source == .voice {
            Label("Voice entry", systemImage: "waveform")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
        } else if entry.source == .watch {
            Label("Written on Apple Watch", systemImage: "applewatch")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Gives list cards the same quick press response as the app's buttons.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
