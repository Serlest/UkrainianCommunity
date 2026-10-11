import SwiftUI

struct AuthMethodButtonLabel: View {
    let title: String
    let icon: Icon

    enum Icon {
        case asset(String)
        case system(String)
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch icon {
                case .asset(let name):
                    Image(name).resizable()
                case .system(let name):
                    Image(systemName: name).resizable().scaledToFit()
                }
            }
            .frame(width: 18, height: 18)

            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.vertical, 1)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.black.opacity(0.18))
        }
    }
}
