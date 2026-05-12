[
  layers: [
    application: "AshCredo.Application",
    cache: "AshCredo.Cache",
    orchestration: ["AshCredo.Orchestration", "AshCredo.ClearCacheTask"],
    introspection: "AshCredo.Introspection.*",
    path_filter: "AshCredo.PathFilter",
    checks: "AshCredo.Check.*",
    self_check: "AshCredo.SelfCheck.*",
    mix_tasks: "Mix.Tasks.*"
  ],
  deps: [
    forbidden: [
      # cache is foundational; nothing in our code may be reached from it
      {:cache, :application},
      {:cache, :orchestration},
      {:cache, :introspection},
      {:cache, :path_filter},
      {:cache, :checks},
      {:cache, :self_check},
      {:cache, :mix_tasks},

      # application only boots cache via the supervisor
      {:application, :orchestration},
      {:application, :introspection},
      {:application, :path_filter},
      {:application, :checks},
      {:application, :self_check},
      {:application, :mix_tasks},

      # introspection sits above cache only
      {:introspection, :orchestration},
      {:introspection, :path_filter},
      {:introspection, :checks},
      {:introspection, :self_check},
      {:introspection, :application},
      {:introspection, :mix_tasks},

      # orchestration sits between introspection and checks; never reaches up or sideways into path_filter
      {:orchestration, :path_filter},
      {:orchestration, :checks},
      {:orchestration, :self_check},
      {:orchestration, :application},
      {:orchestration, :mix_tasks},

      # path_filter is a pure leaf utility consumed only by checks
      {:path_filter, :cache},
      {:path_filter, :application},
      {:path_filter, :orchestration},
      {:path_filter, :introspection},
      {:path_filter, :checks},
      {:path_filter, :self_check},
      {:path_filter, :mix_tasks},

      # checks are leaves from the lint pipeline's POV
      {:checks, :self_check},
      {:checks, :application},
      {:checks, :mix_tasks},

      # self_check only inspects source via introspection; never reaches sideways or up
      {:self_check, :cache},
      {:self_check, :path_filter},
      {:self_check, :orchestration},
      {:self_check, :checks},
      {:self_check, :application},
      {:self_check, :mix_tasks}
    ]
  ]
]
