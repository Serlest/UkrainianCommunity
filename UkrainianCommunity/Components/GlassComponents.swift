import SwiftUI

enum AppGlassFallbackRole {
    case surface
    case control

    func color(for colorScheme: ColorScheme, reduceTransparency: Bool) -> Color {
        if reduceTransparency {
            return AppTheme.glassFallbackSurface(for: colorScheme)
        }

        switch self {
        case .surface:
            return AppTheme.glassSurface(for: colorScheme)
        case .control:
            return AppTheme.glassControlSurface(for: colorScheme)
        }
    }
}

/// Shared Liquid Glass surface for custom app components.
///
/// iOS 26 uses the native effect. Earlier systems and Reduce Transparency use
/// the existing semantic material treatment so controls stay legible and the
/// app keeps the same hierarchy across supported OS versions.
struct AppGlassSurfaceStyle: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let isInteractive: Bool
    let usesNativeGlass: Bool
    let fallbackMaterial: Material
    let fallbackRole: AppGlassFallbackRole
    let fallbackSurface: Color?
    let fallbackUsesMaterial: Bool
    let fallbackBorder: Color?
    let borderOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), usesNativeGlass, !reduceTransparency {
            content
                .glassEffect(
                    nativeGlass,
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            fallbackSurface(for: content)
        }
    }

    @available(iOS 26.0, *)
    private var nativeGlass: Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        return glass.interactive(isInteractive)
    }

    private func fallbackSurface(for content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let baseSurface: Color

        if reduceTransparency {
            if tint != nil, let fallbackSurface {
                baseSurface = fallbackSurface.opacity(0.96)
            } else {
                baseSurface = AppTheme.glassFallbackSurface(for: colorScheme)
            }
        } else {
            baseSurface = fallbackSurface
                ?? tint?.opacity(0.82)
                ?? fallbackRole.color(
                    for: colorScheme,
                    reduceTransparency: false
                )
        }

        return content
            .background {
                shape.fill(baseSurface)
            }
            .background {
                if fallbackUsesMaterial && !reduceTransparency {
                    shape.fill(fallbackMaterial)
                }
            }
            .overlay {
                shape.strokeBorder(
                    (fallbackBorder ?? AppTheme.glassBorder(for: colorScheme))
                        .opacity(borderOpacity)
                )
            }
            .shadow(
                color: AppTheme.glassShadow(for: colorScheme),
                radius: shadowRadius,
                y: shadowY
            )
    }
}

extension View {
    func appGlassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        isInteractive: Bool = false,
        usesNativeGlass: Bool = false,
        fallbackMaterial: Material = .ultraThinMaterial,
        fallbackRole: AppGlassFallbackRole = .surface,
        fallbackSurface: Color? = nil,
        fallbackUsesMaterial: Bool = true,
        fallbackBorder: Color? = nil,
        borderOpacity: Double = AppTheme.glassCardBorderOpacity,
        shadowRadius: CGFloat = AppTheme.glassCardShadowRadius,
        shadowY: CGFloat = AppTheme.glassCardShadowY
    ) -> some View {
        modifier(
            AppGlassSurfaceStyle(
                cornerRadius: cornerRadius,
                tint: tint,
                isInteractive: isInteractive,
                usesNativeGlass: usesNativeGlass,
                fallbackMaterial: fallbackMaterial,
                fallbackRole: fallbackRole,
                fallbackSurface: fallbackSurface,
                fallbackUsesMaterial: fallbackUsesMaterial,
                fallbackBorder: fallbackBorder,
                borderOpacity: borderOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}

/// Groups nearby native effects so SwiftUI can render them together. The
/// wrapper has no visual effect on older systems or with Reduce Transparency.
struct AppGlassEffectGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
