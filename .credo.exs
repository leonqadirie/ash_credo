%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/test/integration/fixtures/"]
      },
      plugins: [{ExDNA.Credo, []}],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        extra: [
          # ExSlop - Warning Checks
          {ExSlop.Check.Warning.BlanketRescue, []},
          {ExSlop.Check.Warning.RescueWithoutReraise, []},
          {ExSlop.Check.Warning.RepoAllThenFilter, []},
          {ExSlop.Check.Warning.QueryInEnumMap, []},
          {ExSlop.Check.Warning.GenserverAsKvStore, []},
          {ExSlop.Check.Warning.PathExpandPriv, []},
          {ExSlop.Check.Warning.DualKeyAccess, []},

          # ExSlop - Refactor Checks
          {ExSlop.Check.Refactor.FilterNil, []},
          {ExSlop.Check.Refactor.RejectNil, []},
          {ExSlop.Check.Refactor.ReduceAsMap, []},
          {ExSlop.Check.Refactor.MapIntoLiteral, []},
          {ExSlop.Check.Refactor.IdentityPassthrough, []},
          {ExSlop.Check.Refactor.IdentityMap, []},
          {ExSlop.Check.Refactor.CaseTrueFalse, []},
          {ExSlop.Check.Refactor.TryRescueWithSafeAlternative, []},
          {ExSlop.Check.Refactor.WithIdentityElse, []},
          {ExSlop.Check.Refactor.WithIdentityDo, []},
          {ExSlop.Check.Refactor.SortThenReverse, []},
          {ExSlop.Check.Refactor.StringConcatInReduce, []},
          {ExSlop.Check.Refactor.ReduceMapPut, []},
          {ExSlop.Check.Refactor.RedundantBooleanIf, []},
          {ExSlop.Check.Refactor.FlatMapFilter, []},
          {ExSlop.Check.Refactor.RedundantEnumJoinSeparator, []},
          {ExSlop.Check.Refactor.UseMapJoin, []},
          {ExSlop.Check.Refactor.PreferEnumSlice, []},
          {ExSlop.Check.Refactor.GraphemesLength, []},
          {ExSlop.Check.Refactor.ManualStringReverse, []},
          {ExSlop.Check.Refactor.SortThenAt, []},
          {ExSlop.Check.Refactor.SortForTopK, []},
          {ExSlop.Check.Refactor.ListFold, []},
          {ExSlop.Check.Refactor.ListLast, []},
          {ExSlop.Check.Refactor.LengthInGuard, []},
          {ExSlop.Check.Refactor.LengthComparison, []},
          {ExSlop.Check.Refactor.ExplicitSumReduce, []},

          # ExSlop - Readability Checks
          {ExSlop.Check.Readability.NarratorDoc, []},
          {ExSlop.Check.Readability.DocFalseOnPublicFunction, []},
          {ExSlop.Check.Readability.BoilerplateDocParams, []},
          {ExSlop.Check.Readability.ObviousComment, [additional_keywords: []]},
          {ExSlop.Check.Readability.StepComment, []},
          {ExSlop.Check.Readability.NarratorComment, []},
          {ExSlop.Check.Readability.UnaliasedModuleUse, []},

          # Internal - enforce architectural invariants. The compiled
          # introspection boundary (only AshCredo.Introspection.Compiled may
          # call Ash's runtime introspection modules) is enforced structurally
          # via the `calls.forbidden` policy in .reach.exs, run by `mix lint`.
          {AshCredo.SelfCheck.EnforceCompiledCheckWrapper, []}
        ]
      }
    }
  ]
}
