import Foundation

/// A Windows runtime or library that can be installed into a bottle with winetricks.
/// Many programs that "don't work" under Wine just need one of these.
struct WindowsComponent: Identifiable, Hashable {
    let verb: String          // winetricks verb
    let name: String
    let detail: String
    let category: Category
    var essential = false     // installed automatically during first-time setup

    var id: String { verb }

    enum Category: String, CaseIterable, Identifiable {
        case runtimes = "Runtimes"
        case directx = "DirectX & Gaming"
        case fonts = "Fonts"
        case media = "Media"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .runtimes: return "shippingbox"
            case .directx: return "gamecontroller"
            case .fonts: return "textformat"
            case .media: return "play.rectangle"
            }
        }
    }
}

enum ComponentCatalog {
    static let all: [WindowsComponent] = [
        // Runtimes
        .init(verb: "vcrun2022", name: "Visual C++ 2015–2022", detail: "Needed by most modern apps and games.", category: .runtimes, essential: true),
        .init(verb: "vcrun2013", name: "Visual C++ 2013", detail: "Older games and tools.", category: .runtimes),
        .init(verb: "vcrun2012", name: "Visual C++ 2012", detail: "Older games and tools.", category: .runtimes),
        .init(verb: "vcrun2010", name: "Visual C++ 2010", detail: "Games from roughly 2010–2014.", category: .runtimes),
        .init(verb: "vcrun2008", name: "Visual C++ 2008", detail: "Older software.", category: .runtimes),
        .init(verb: "vcrun2005", name: "Visual C++ 2005", detail: "Very old software.", category: .runtimes),
        .init(verb: "dotnet48", name: ".NET Framework 4.8", detail: "Classic .NET desktop apps. Large; takes several minutes.", category: .runtimes),
        .init(verb: "dotnetdesktop8", name: ".NET 8 Desktop Runtime", detail: "Modern .NET (WPF / WinForms) apps.", category: .runtimes),
        .init(verb: "dotnetdesktop6", name: ".NET 6 Desktop Runtime", detail: "Modern .NET apps built on version 6.", category: .runtimes),
        .init(verb: "xna40", name: "XNA Framework 4.0", detail: "Indie games such as Terraria-era titles.", category: .runtimes),

        // DirectX & gaming
        .init(verb: "d3dx9", name: "DirectX 9 (D3DX9)", detail: "Libraries used by thousands of DirectX 9 games.", category: .directx, essential: true),
        .init(verb: "d3dcompiler_47", name: "D3D Shader Compiler 47", detail: "Shader compiler for DirectX 11 games and many apps.", category: .directx, essential: true),
        .init(verb: "d3dx10_43", name: "DirectX 10 (D3DX10)", detail: "Helper libraries for DirectX 10 games.", category: .directx),
        .init(verb: "d3dx11_43", name: "DirectX 11 (D3DX11)", detail: "Helper libraries for DirectX 11 games.", category: .directx),
        .init(verb: "xact", name: "XACT Audio", detail: "Fixes missing sound in many older games.", category: .directx),
        .init(verb: "xinput", name: "XInput", detail: "Game controller support for older games.", category: .directx),
        .init(verb: "physx", name: "NVIDIA PhysX", detail: "Physics engine some games require.", category: .directx),

        // Fonts
        .init(verb: "corefonts", name: "Microsoft Core Fonts", detail: "Arial, Times New Roman, Verdana and more; fixes garbled text.", category: .fonts, essential: true),
        .init(verb: "tahoma", name: "Tahoma", detail: "Default Windows UI font used by older programs.", category: .fonts),
        .init(verb: "cjkfonts", name: "Chinese, Japanese & Korean fonts", detail: "Shows Asian text instead of boxes.", category: .fonts),

        // Media
        .init(verb: "quartz", name: "DirectShow (quartz)", detail: "Video playback in older games and apps.", category: .media),
        .init(verb: "lavfilters", name: "LAV Filters", detail: "Decoders for in-game videos and cutscenes.", category: .media),
        .init(verb: "wmp10", name: "Windows Media Player 10", detail: "Media playback some programs depend on.", category: .media),
    ]

    static var essentials: [WindowsComponent] { all.filter(\.essential) }
}
