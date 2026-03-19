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
        assets = [asset("assets/favicon.png", class=:ico)],
    ),
    authors = "João Pinelo <jp@joaopinelo.com>",
    repo = Documenter.Remotes.GitHub("AIRCentre", "AtlanticCloud.jl"),
)

deploydocs(
    repo = "github.com/AIRCentre/AtlanticCloud.jl.git",
    devbranch = "main",
    push_preview = false,
)
