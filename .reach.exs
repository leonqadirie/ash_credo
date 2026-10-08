[
  layers: [
    plugin: "AshCredo",
    application: "AshCredo.Application",
    cache: "AshCredo.Cache",
    orchestration: ["AshCredo.Orchestration", "AshCredo.ClearCacheTask", "AshCredo.CompiledCheck"],
    introspection: ["AshCredo.Introspection", "AshCredo.Introspection.*"],
    path_filter: ["AshCredo.PathFilter", "AshCredo.NameFilter"],
    checks: "AshCredo.Check.*",
    mix_tasks: "Mix.Tasks.*"
  ],
  calls: [
    # Structural enforcement of the introspection boundary: all Ash runtime
    # introspection must go through AshCredo.Introspection.Compiled, the single
    # gateway. Any other AshCredo module calling these Ash modules directly is a
    # forbidden call. Resolved against Reach's call graph, so alias-expanded
    # calls (e.g. `alias Ash.Resource.Info, as: ResourceInfo`) are caught too.
    forbidden: [
      {"AshCredo.*",
       [
         "Ash.Resource.Info.*",
         "Ash.Domain.Info.*",
         "Ash.Policy.Info.*",
         "Ash.DataLayer.Ets.Info.*",
         "Ash.DataLayer.Mnesia.Info.*",
         "Ash.Notifier.PubSub.Info.*",
         "Ash.TypedStruct.Info.*",
         "Ash.Type.NewType.*",
         "Ash.Type.*"
       ], except: ["AshCredo.Introspection.Compiled"]},
      # The same gateway owns module loading and BEAM chunk reads, so checks
      # never load target modules or read their specs on their own.
      {"AshCredo.*",
       [
         "Code.ensure_loaded*",
         "Code.ensure_compiled*",
         "Code.Typespec.*",
         "Code.fetch_docs"
       ], except: ["AshCredo.Introspection.Compiled"]}
    ]
  ],
  deps: [
    # Allowlist mode: Reach reports every cross-layer edge not listed here,
    # including edges into layers added later. Same-layer calls stay allowed.
    mode: :allowlist,
    allowed: [
      # the Credo plugin entry point only resets the cache
      plugin: [:cache],
      # application only boots cache via the supervisor
      application: [:cache],
      # cache is foundational; it reaches nothing in our code
      cache: [],
      # orchestration sits between introspection and checks
      orchestration: [:cache, :introspection],
      # introspection sits above cache only
      introspection: [:cache],
      # path_filter is a pure leaf utility consumed only by checks
      path_filter: [],
      # checks are leaves from the lint pipeline's POV
      checks: [:cache, :orchestration, :introspection, :path_filter],
      mix_tasks: []
    ]
  ],
  effects: [
    # Only the cache and its supervisor own ETS writes and IO. Everything the
    # lint pipeline runs must stay free of IO, writes, and message passing.
    # :read covers Code.ensure_loaded/1 probes.
    by_layer: [
      plugin: [:pure, :unknown, :exception, :read],
      application: :any,
      cache: :any,
      orchestration: [:pure, :unknown, :exception, :read],
      introspection: [:pure, :unknown, :exception, :read],
      path_filter: [:pure, :unknown, :exception, :read],
      checks: [:pure, :unknown, :exception, :read],
      mix_tasks: :any
    ]
  ],
  checks: [
    # Fixed source set so the verdict does not depend on MIX_ENV.
    source_paths: ["lib", "dev"],
    layer_coverage: [require_all_modules: true, forbid_multiple_matches: true]
  ],
  smells: [strict: true]
]
