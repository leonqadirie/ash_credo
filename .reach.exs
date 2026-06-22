[
  layers: [
    application: "AshCredo.Application",
    cache: "AshCredo.Cache",
    orchestration: ["AshCredo.Orchestration", "AshCredo.ClearCacheTask", "AshCredo.CompiledCheck"],
    introspection: "AshCredo.Introspection.*",
    path_filter: "AshCredo.PathFilter",
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
       ], except: ["AshCredo.Introspection.Compiled"]}
    ]
  ],
  deps: [
    forbidden: [
      # cache is foundational; nothing in our code may be reached from it
      {:cache, :application},
      {:cache, :orchestration},
      {:cache, :introspection},
      {:cache, :path_filter},
      {:cache, :checks},
      {:cache, :mix_tasks},

      # application only boots cache via the supervisor
      {:application, :orchestration},
      {:application, :introspection},
      {:application, :path_filter},
      {:application, :checks},
      {:application, :mix_tasks},

      # introspection sits above cache only
      {:introspection, :orchestration},
      {:introspection, :path_filter},
      {:introspection, :checks},
      {:introspection, :application},
      {:introspection, :mix_tasks},

      # orchestration sits between introspection and checks; never reaches up or sideways into path_filter
      {:orchestration, :path_filter},
      {:orchestration, :checks},
      {:orchestration, :application},
      {:orchestration, :mix_tasks},

      # path_filter is a pure leaf utility consumed only by checks
      {:path_filter, :cache},
      {:path_filter, :application},
      {:path_filter, :orchestration},
      {:path_filter, :introspection},
      {:path_filter, :checks},
      {:path_filter, :mix_tasks},

      # checks are leaves from the lint pipeline's POV
      {:checks, :application},
      {:checks, :mix_tasks}
    ]
  ]
]
