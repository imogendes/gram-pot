load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GramPotScreen",
    module_name = "GramPotScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/Components/ViewControllerComponent",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/TelegramUI/Components/ButtonComponent",
        "//submodules/TelegramUI/Components/Wallet/WalletSendKeyboardComponent",
        "//submodules/TelegramStringFormatting",
        "//submodules/TemporaryCachedPeerDataManager",
    ],
    visibility = [
        "//visibility:public",
    ],
)
