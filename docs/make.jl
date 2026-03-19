using Documenter
using AtlanticCloud

makedocs(
    sitename = "AtlanticCloud.jl",
    modules = [AtlanticCloud],
    pages = [
        "Home" => "index.md",
        "API Reference" => "api.md",
        "Examples" => "examples.md",
    ],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://AIRCentre.github.io/AtlanticCloud.jl",
        assets = ["assets/favicon.ico"],
    ),
    authors = "João Pinelo <joao.pinelo@aircentre.org>",
    repo = Documenter.Remotes.GitHub("AIRCentre", "AtlanticCloud.jl"),
)

deploydocs(
    repo = "github.com/AIRCentre/AtlanticCloud.jl.git",
    devbranch = "main",
    push_preview = false,
)
