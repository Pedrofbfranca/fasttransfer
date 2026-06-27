import SwiftUI

enum AppTab: String, CaseIterable {
    case transfer = "Transferir"
    case history = "Histórico"

    var icon: String {
        switch self {
        case .transfer: return "arrow.right.circle.fill"
        case .history: return "clock.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var transferManager: TransferManager
    @State private var selectedTab: AppTab = .transfer

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
        } detail: {
            switch selectedTab {
            case .transfer:
                TransferView()
            case .history:
                HistoryView()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SidebarView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject var transferManager: TransferManager

    var body: some View {
        VStack(spacing: 0) {
            // App header
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("FastTransfer")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .padding(.vertical, 20)

            Divider()

            // Nav items
            VStack(spacing: 2) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    SidebarItem(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.top, 8)

            Spacer()

            // Active jobs badge
            if !transferManager.activeJobs.isEmpty {
                HStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                    Text("\(transferManager.activeJobs.count) em progresso")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }

            Text("Desenvolvido por Pedro França")
                .font(.system(size: 9))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct SidebarItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .frame(width: 20)
                Text(tab.rawValue)
                    .font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
