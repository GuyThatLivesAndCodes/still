import SwiftUI

/// First-run intro: what still. is, interactive demos, then Terms + Privacy.
struct OnboardingView: View {
    var startAtTerms: Bool = false
    var onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, write, seal, reveal, streak, privacy, everywhere, about, terms
    }

    @State private var step: Step = .welcome
    @State private var forward = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ZStack {
                    page(step)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if step != .terms {
                    Button(step == .welcome ? "Begin" : "Continue") { go(+1) }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard step != .terms || value.translation.width > 0 else { return }
            if value.translation.width < -60 { go(+1) }
            if value.translation.width > 60 { go(-1) }
        })
        .onAppear { if startAtTerms { step = .terms } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { go(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .glass(22)
            }
            .buttonStyle(.plain)
            .opacity(step == .welcome || startAtTerms ? 0 : 1)
            .disabled(step == .welcome || startAtTerms)
            .accessibilityLabel("Back")

            HStack(spacing: 4) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Theme.ink : Color.white.opacity(0.14))
                        .frame(height: 3)
                }
            }
            .opacity(startAtTerms ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: step)
            .accessibilityHidden(true)

            if step != .terms && !startAtTerms {
                Button("Skip") { go(to: .terms) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome: WelcomePage()
        case .write: WriteDemoPage()
        case .seal: SealDemoPage()
        case .reveal: RevealDemoPage()
        case .streak: StreakDemoPage()
        case .privacy: PrivacyIntroPage()
        case .everywhere: EverywherePage()
        case .about: AboutYouPage()
        case .terms: TermsPage(onAccept: onFinish)
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        go(to: next)
    }

    private func go(to next: Step) {
        forward = next.rawValue > step.rawValue
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { step = next }
    }
}

// MARK: - Shared page layout

private struct PageLayout<Demo: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder var demo: Demo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 12)
            demo
                .frame(maxWidth: .infinity)
                .frame(height: 280)
            Spacer(minLength: 12)
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 8)
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .kerning(-1.2)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)
            Text(detail)
                .font(.system(size: 17))
                .lineSpacing(3)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    @State private var phase = 0

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("still.")
                .font(.system(size: 64, weight: .semibold))
                .kerning(-3)
                .foregroundStyle(Theme.ink)
                .scaleEffect(phase >= 1 ? 1 : 0.92)
                .opacity(phase >= 1 ? 1 : 0)
                .blur(radius: phase >= 1 ? 0 : 8)
            Text("Some things are better left in the moment.")
                .font(.system(size: 17))
                .foregroundStyle(Theme.secondary)
                .opacity(phase >= 2 ? 1 : 0)
                .offset(y: phase >= 2 ? 0 : 8)
            Spacer()
            Text("A private journal for how you feel right now.\nWrite it, seal it, and let it go.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.tertiary)
                .opacity(phase >= 3 ? 1 : 0)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .task {
            for p in 1...3 {
                try? await Task.sleep(for: .milliseconds(p == 1 ? 150 : 650))
                withAnimation(.easeOut(duration: 0.9)) { phase = p }
            }
        }
    }
}

private struct WriteDemoPage: View {
    private let sample = "Long day. I'm proud I didn't snap at anyone, even when I wanted to."
    @State private var expanded = false
    @State private var typed = ""
    @State private var sealed = false
    @State private var typing: Task<Void, Never>?

    var body: some View {
        PageLayout(eyebrow: "Step one",
                   title: "Write it.",
                   detail: "Whatever's on your mind, in the moment. No titles, no formatting, no rereading. Try it: tap the box.") {
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    if sealed {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                            Text("Sealed until midnight, \(Entry.sealDays) days from now")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else if expanded {
                        Text(typed + (typed.count < sample.count ? "|" : ""))
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(16)
                            .transition(.opacity)
                    } else {
                        Button(action: expand) {
                            HStack(spacing: 10) {
                                Image(systemName: "pencil.line")
                                Text("Write")
                            }
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: expanded ? .infinity : 260)
                .frame(height: sealed ? 64 : (expanded ? 150 : 52))
                .glass(expanded ? 24 : 26)

                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { sealed = true }
                } label: {
                    Label("Seal", systemImage: "lock")
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !typed.isEmpty && !sealed))
                .disabled(typed.isEmpty || sealed)
                .frame(width: 200)
                .opacity(sealed ? 0 : 1)
                Spacer()
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: expanded)
        }
        .onDisappear { typing?.cancel() }
    }

    private func expand() {
        expanded = true
        typing = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            for ch in sample {
                if Task.isCancelled { return }
                typed.append(ch)
                try? await Task.sleep(for: .milliseconds(ch == " " ? 55 : 32))
            }
        }
    }
}

private struct SealDemoPage: View {
    @State private var day = 0
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: Entry.sealDays + 1)

    var body: some View {
        PageLayout(eyebrow: "Step two",
                   title: "Seal it.",
                   detail: "Once sealed, an entry can't be changed. It rests out of reach and opens at midnight on the \(Entry.sealDays)th day, so you can put it down and move on.") {
            VStack(spacing: 16) {
                Spacer()
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0...Entry.sealDays, id: \.self) { i in
                        let isOpen = i == Entry.sealDays
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(i <= day ? (isOpen ? Theme.accent : Color.white.opacity(0.16)) : Color.white.opacity(0.05))
                            .overlay {
                                if i == 0 {
                                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.ink)
                                } else if isOpen {
                                    Text("Opens")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(i <= day ? Color.black : Theme.tertiary)
                                } else {
                                    Text("\(i)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.tertiary)
                                }
                            }
                            .frame(height: 52)
                    }
                }
                .frame(maxWidth: 300)
                Text(day >= Entry.sealDays ? "Day \(Entry.sealDays) · 12:00 AM" : "Day \(day)")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .contentTransition(.numericText())
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("An entry sealed today opens at midnight on day \(Entry.sealDays).")
        }
        .task {
            day = 0
            try? await Task.sleep(for: .milliseconds(400))
            for d in 1...Entry.sealDays {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeOut(duration: 0.2)) { day = d }
            }
        }
    }
}

private struct RevealDemoPage: View {
    @State private var revealed = false
    @State private var left = 5

    var body: some View {
        PageLayout(eyebrow: "Step three",
                   title: "Let it go.",
                   detail: "When an entry opens, tap to read it, then let it rest again. If you really need one sooner, you get 2 early reveals a week.") {
            VStack(spacing: 18) {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Sat, Oct 24 · Night").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: revealed ? "timer" : "lock")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(revealed ? Theme.accent : Theme.ink)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .foregroundStyle(Theme.ink)
                    Text("I finally said no to the extra project. Felt guilty for an hour, then lighter than I have in weeks.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                        .invisibleInk(!revealed, tint: Theme.ink)
                }
                .padding(18)
                .glass(22)
                .frame(maxWidth: 320)
                .contentShape(Rectangle())
                .onTapGesture { revealed ? reseal() : reveal() }

                Button(revealed ? "Reseal now" : "Reveal") { revealed ? reseal() : reveal() }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(width: 180)
                Spacer()
            }
        }
    }

    private func reveal() {
        left = 5
        withAnimation(.easeOut(duration: 0.5)) { revealed = true }
        Task { @MainActor in
            while left > 0 && revealed {
                try? await Task.sleep(for: .seconds(1))
                guard revealed else { return }
                withAnimation { left -= 1 }
            }
            reseal()
        }
    }

    private func reseal() {
        withAnimation(.easeIn(duration: 0.5)) { revealed = false }
    }
}

private struct StreakDemoPage: View {
    @State private var count = 0
    @State private var fill = 0.0

    var body: some View {
        PageLayout(eyebrow: "If you like",
                   title: "Gentle, never guilty.",
                   detail: "Write once every 36 hours to keep a streak. You get 2 free revives a year, and you can hide the streak completely.") {
            VStack(spacing: 22) {
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(count)")
                        .font(.system(size: 72, weight: .semibold))
                        .kerning(-3)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("days").font(.title3).foregroundStyle(Theme.secondary)
                }
                .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(Theme.accent).frame(width: geo.size.width * fill)
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("36-hour window").font(.caption).foregroundStyle(Theme.tertiary)
                        Spacer()
                        Label("2 revives", systemImage: "heart").font(.caption).foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(maxWidth: 280)
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Example streak of 7 days")
        }
        .task {
            for c in 1...7 {
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.snappy) { count = c }
            }
            withAnimation(.easeInOut(duration: 1.2)) { fill = 0.72 }
        }
    }
}

private struct PrivacyIntroPage: View {
    @State private var shown = 0
    private let items: [(String, String)] = [
        ("lock.shield", "Encrypted on your iPhone"),
        ("person.crop.circle.badge.xmark", "No account, ads, or tracking"),
        ("faceid", "Optional Face ID lock"),
        ("iphone", "Stays here unless you allow it")
    ]

    var body: some View {
        PageLayout(eyebrow: "Privacy",
                   title: "Yours alone.",
                   detail: "Everything you write is encrypted before it's saved, and the key stays on this iPhone. Not even we can read it.") {
            VStack(spacing: 10) {
                Spacer()
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 14) {
                        Image(systemName: item.0)
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        Text(item.1).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .glass(18)
                    .opacity(i < shown ? 1 : 0)
                    .offset(y: i < shown ? 0 : 10)
                }
                Spacer()
            }
        }
        .task {
            for i in 1...items.count {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { shown = i }
            }
        }
    }
}

private struct EverywherePage: View {
    private let tiles: [(String, String)] = [
        ("square.grid.2x2", "Home & Lock Screen widgets"),
        ("switch.2", "Control Center & Action Button"),
        ("waveform", "\u{201C}Write in still.\u{201D} with Siri"),
        ("applewatch", "Apple Watch")
    ]
    private let grid = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        PageLayout(eyebrow: "Always close",
                   title: "One tap away.",
                   detail: "Add a widget or a control and still. opens straight to a blank page whenever something's on your mind.") {
            VStack {
                Spacer()
                LazyVGrid(columns: grid, spacing: 10) {
                    ForEach(tiles, id: \.1) { tile in
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: tile.0)
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.accent)
                            Text(tile.1)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .padding(14)
                        .glass(20)
                    }
                }
                Spacer()
            }
        }
    }
}

private struct AboutYouPage: View {
    @AppStorage(Profile.nameKey) private var name = ""
    @AppStorage(Profile.birthdayKey) private var birthday: Double = 0
    @AppStorage(Profile.genderKey) private var genderRaw = Gender.unset.rawValue
    @AppStorage(Profile.genderOtherKey) private var genderOther = ""
    @FocusState private var field: Field?

    private enum Field { case name, other }
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Optional")
                        .font(.caption.weight(.semibold))
                        .kerning(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                    Text("A little about you.")
                        .font(.system(size: 34, weight: .semibold))
                        .kerning(-1.2)
                        .foregroundStyle(Theme.ink)
                    Text("Quiet AI uses this to word its notes and replies for you. It stays on this iPhone, and you can change it in You anytime.")
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What should still. call you?").sectionLabel()
                    TextField("First name", text: $name)
                        .focused($field, equals: .name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .glass(16)
                        .onChange(of: name) { _, v in if v.count > 40 { name = String(v.prefix(40)) } }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Date of birth").sectionLabel()
                    HStack {
                        if birthday == 0 {
                            Button {
                                field = nil
                                birthday = ProfileDefaults.suggestedBirthday.timeIntervalSince1970
                            } label: {
                                Label("Add birthday", systemImage: "plus")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Theme.accent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            DatePicker("Birthday", selection: birthdayBinding, in: ProfileDefaults.birthdayRange,
                                       displayedComponents: .date)
                                .foregroundStyle(Theme.ink)
                                .tint(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .glass(16)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Gender").sectionLabel()
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Gender.choices) { option in
                            let selected = genderRaw == option.rawValue
                            Button {
                                withAnimation(.snappy) {
                                    genderRaw = selected ? Gender.unset.rawValue : option.rawValue
                                }
                                if option == .other && !selected { field = .other } else { field = nil }
                            } label: {
                                Text(option.title)
                                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(selected ? Color.black : Theme.ink)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(selected ? Theme.ink : Color.white.opacity(0.06),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Theme.hairline, lineWidth: selected ? 0 : 1))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    if genderRaw == Gender.other.rawValue {
                        TextField("How you describe it", text: $genderOther)
                            .focused($field, equals: .other)
                            .submitLabel(.done)
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .glass(16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .onChange(of: genderOther) { _, v in
                                if v.count > 30 { genderOther = String(v.prefix(30)) }
                            }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { field = nil }
    }

    private var birthdayBinding: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: birthday) },
                set: { birthday = $0.timeIntervalSince1970 })
    }
}

private struct TermsPage: View {
    var onAccept: () -> Void
    @State private var agreedTerms = false
    @State private var agreedPrivacy = false
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Before you begin")
                        .font(.system(size: 34, weight: .semibold))
                        .kerning(-1.2)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 20)
                    Text("The short version:")
                        .font(.body)
                        .foregroundStyle(Theme.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        point("lock", "Your journal stays on this iPhone, encrypted. We collect nothing.")
                        point("heart.text.square", "still. isn't therapy or a crisis service. If you're in danger, contact emergency services (988 in the US).")
                        point("trash", "Deleted entries are gone for good, and sealed entries can't be recovered if this device is lost.")
                        point("person", "You need to be 13 or older.")
                    }
                    .padding(18)
                    .card(22)

                    VStack(spacing: 10) {
                        AgreeRow(isOn: $agreedTerms, label: "I've read and agree to the", link: "Terms of Use") { showTerms = true }
                        AgreeRow(isOn: $agreedPrivacy, label: "I've read and understand the", link: "Privacy Policy") { showPrivacy = true }
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)

            Button("Enter still.") {
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "acceptedTermsAt")
                onAccept()
            }
            .buttonStyle(PrimaryButtonStyle(enabled: agreedTerms && agreedPrivacy))
            .disabled(!(agreedTerms && agreedPrivacy))
            .animation(.easeInOut(duration: 0.25), value: agreedTerms && agreedPrivacy)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showTerms) { LegalSheet(title: "Terms of Use", sections: LegalText.terms) }
        .sheet(isPresented: $showPrivacy) { LegalSheet(title: "Privacy Policy", sections: LegalText.privacy) }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AgreeRow: View {
    @Binding var isOn: Bool
    let label: String
    let link: String
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isOn.toggle() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(isOn ? Theme.ink : Color.white.opacity(0.3), lineWidth: 1.5)
                        .background(Circle().fill(isOn ? Theme.ink : .clear))
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 26, height: 26)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label) \(link)")
            .accessibilityAddTraits(isOn ? .isSelected : [])

            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).foregroundStyle(Theme.secondary)
                Button(link, action: open)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .card(18)
    }
}
