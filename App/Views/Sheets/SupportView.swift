import SwiftUI
import AppKit

struct SupportView: View {
    private let contentWidth: CGFloat = 372
    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5"
    }

    var body: some View {
        ZStack {
            AppTheme.windowGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleHeader
                    supportCard
                }
                .frame(width: contentWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 440, height: 600)
        .preferredColorScheme(.dark)
    }

    private var titleHeader: some View {
        HStack(spacing: 12) {
            Image("LogoGogoLabs")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: -4) {
                HStack(alignment: .top) {
                    Text("Odile")
                        .font(.custom("Lobster", size: 38))
                        .foregroundColor(.white)

                    Text("v" + versionString)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent.opacity(0.2))
                        .foregroundColor(AppTheme.accent)
                        .clipShape(Capsule())
                        .padding(.top, 14)
                }

                Text("EDL Maker assistant")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(.bottom, 10)
    }

    private var supportCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Support")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                guidePanel(
                    icon: "envelope.fill",
                    title: "Contact Support",
                    body: "Opens a prefilled email draft with app and macOS version details.",
                    action: {
                        let sysVer = ProcessInfo.processInfo.operatingSystemVersionString
                        let body = "Application: Odile v\(versionString)\\nmacOS: \(sysVer)\\n\\nIssue Description:\\n"
                        if let url = URL(string: "mailto:support@gogolabs.fr?subject=Odile%20Support&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                guidePanel(
                    icon: "checklist",
                    title: "Before contacting support",
                    body: "Include the detailed action you tried, and whether the issue happened during PTSL sync, XLSX export, or markers."
                )
            }
            .padding(20)
            .background(AppTheme.cardElevated)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                    .stroke(AppTheme.softBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        }
    }

    private func guidePanel(icon: String, title: String, body colBody: String, action: (() -> Void)? = nil) -> some View {
        Button(action: {
            action?()
        }) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(colBody)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardElevated.opacity(action != nil ? 0.8 : 0.0))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
