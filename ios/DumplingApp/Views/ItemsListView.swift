import SwiftUI
import SwiftData

struct ItemsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]

    var body: some View {
        ZStack {
            Color.dCream.ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar

                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { item in
                                ItemRowView(item: item)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .onAppear(perform: importPendingItems)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { importPendingItems() }
        }
    }

    // MARK: - Sub-views

    private var titleBar: some View {
        HStack {
            Text("📥 RECENT DUMPS")
                .font(.custom("Courier New", size: 11).bold())
                .foregroundColor(.dBlack)
            Spacer()
            Text("\(items.count)")
                .font(.custom("Courier New", size: 10).bold())
                .foregroundColor(.dBlack)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.dButter)
                .pixelBorder(width: 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.dBlue)
        .overlay(Rectangle().frame(height: 3).foregroundColor(.dBlack), alignment: .bottom)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🥟")
                .font(.system(size: 48))
            Text("NO DUMPS YET")
                .font(.custom("Courier New", size: 14).bold())
                .foregroundColor(.dBlack)
            Text("Share something from any app\nto see it here.")
                .font(.custom("Courier New", size: 11))
                .foregroundColor(.dBlack.opacity(0.5))
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Queue import

    private func importPendingItems() {
        let pending = AppGroup.dequeueAll()
        for p in pending {
            let item = Item(
                contentURL: p.contentURL,
                contentText: p.contentText,
                sourceApp: p.sourceApp,
                userNote: p.userNote,
                quickTag: p.quickTag
            )
            item.timestamp = p.timestamp
            modelContext.insert(item)
        }
        if !pending.isEmpty {
            try? modelContext.save()
        }
    }
}

// MARK: - Row

struct ItemRowView: View {
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.sourceEmoji)
                .font(.system(size: 20))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.custom("Courier New", size: 11))
                    .foregroundColor(.dBlack)
                    .lineLimit(2)

                if let note = item.userNote {
                    Text("✎ \(note)")
                        .font(.custom("Courier New", size: 10).italic())
                        .foregroundColor(.dBlack.opacity(0.7))
                        .lineLimit(3)
                }

                HStack(spacing: 6) {
                    if let tag = item.quickTag {
                        Text(tag.uppercased())
                            .font(.custom("Courier New", size: 8).bold())
                            .foregroundColor(.dBlack)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: item.tagColor))
                            .pixelBorder(width: 1)
                    }

                    Text(item.timestamp.formatted(.relative(presentation: .named)))
                        .font(.custom("Courier New", size: 9))
                        .foregroundColor(.dBlack.opacity(0.5))
                }
            }

            Spacer()

            statusDot
        }
        .padding(10)
        .pixelCard()
    }

    private var statusDot: some View {
        Circle()
            .fill(item.status == "pending" ? Color.dButter : item.status == "routed" ? Color.dMint : Color.dPink)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Color.dBlack, lineWidth: 1))
    }
}
