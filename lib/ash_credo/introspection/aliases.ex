defmodule AshCredo.Introspection.Aliases do
  @moduledoc false

  @directive_kinds ~w(alias require import)a

  @doc """
  Returns a fresh `Macro.Env` for accumulating lexical directives.

  Built via `Code.env_for_eval/1`, so `Kernel` is pre-required and
  pre-imported exactly as in any real compilation unit. This is only
  observable when a consumer asks `Macro.Env.required?(env, Kernel)`
  before any directive was applied, which mirrors real Elixir semantics
  anyway.
  """
  def base_env do
    Code.env_for_eval(file: "nofile")
  end

  @doc """
  Applies an `alias`/`require`/`import` directive AST node to `env` and
  returns the updated env. Malformed or unresolvable directives leave
  the env unchanged (a graceful skip), matching how unparsable
  directives produced no alias entry before.

  `enclosing` is the absolute segment list of the innermost literal
  `defmodule`, or `nil` when unknown; it substitutes a leading
  `__MODULE__` in the directive target (`alias __MODULE__.Post`) at
  declaration time, which is where Elixir itself resolves it.

  `require Mod, as: Q` registers both the require and the alias.
  `import Mod` is registered via `Macro.Env.define_import/4` when the
  module is loaded in the linting VM (Ash framework modules always are
  in a project running these checks), honoring literal `only:`/`except:`
  selections, so `imported_module/3` can resolve bare calls. Modules
  that are not loadable (user modules in a not-yet-compiled project) and
  imports with non-literal selections (`only: @funs`) fall back to
  `Macro.Env.define_require/4`. Consumers asking whether a require holds
  at a point stay correct either way: import implies require in Elixir,
  and a successful `define_import` marks the module required too
  (verified empirically). They just cannot resolve bare calls through
  that import.
  """
  def apply_directive(%Macro.Env{} = env, directive_ast, enclosing) do
    directive_ast
    |> directive_targets()
    |> Enum.reduce(env, fn {kind, meta, target_segments, as_opts}, acc ->
      apply_target(acc, kind, meta, target_segments, as_opts, enclosing)
    end)
  end

  @doc """
  Resolves alias segments to a module atom through `env`, falling back
  to plain concatenation when no alias matches. Returns `:error` when
  the segments are not a non-empty list of plain atoms (e.g. they still
  carry an `unquote` or `__MODULE__` node).
  """
  def expand_to_module(segments, %Macro.Env{} = env) when is_list(segments) do
    if atom_segments?(segments) do
      case Macro.Env.expand_alias(env, [], segments) do
        {:alias, module} -> {:ok, module}
        :error -> {:ok, Module.concat(segments)}
      end
    else
      :error
    end
  end

  def expand_to_module(_segments, %Macro.Env{}), do: :error

  @doc """
  Resolves a bare (unqualified) call to the module it is imported from,
  via the compiler's own `Macro.Env.lookup_import/2`. Returns
  `{:ok, module}` for the first matching import and `:error` when no
  import in `env` exports `function/arity`, which includes imports that
  were registered as plain requires because their module was not
  loadable.

  Callers must pass the effective arity: a piped call `q |> filter(expr)`
  resolves as `filter/2`, not `filter/1`. Locals shadow imports (a
  genuine conflict does not even compile), so callers that walk source
  where the name/arity is also defined locally must check that before
  trusting this result.
  """
  def imported_module(%Macro.Env{} = env, function, arity)
      when is_atom(function) and is_integer(arity) and arity >= 0 do
    case Macro.Env.lookup_import(env, {function, arity}) do
      [{_kind, module} | _] -> {:ok, module}
      [] -> :error
    end
  end

  @doc """
  Extracts the literal alias segments from a `defmodule` AST node, or
  `nil` when the module name is not a literal alias (e.g.
  `Module.concat(...)`).
  """
  def defmodule_literal_segments({:defmodule, _, [{:__aliases__, _, segs}, _]})
      when is_list(segs), do: segs

  def defmodule_literal_segments(_), do: nil

  @doc """
  Registers the alias a `defmodule` itself creates in the enclosing
  lexical scope: after `defmodule Post do ... end` inside `MyApp.Blog`,
  `Post` refers to `MyApp.Blog.Post` for the rest of the enclosing body.
  A dotted name aliases its first segment (`defmodule Blog.Article`
  inside `MyApp` makes `Blog` mean `MyApp.Blog`). Non-literal names and
  unknown absolute paths register nothing.
  """
  def define_defmodule_alias(%Macro.Env{} = env, defmodule_ast, child_absolute) do
    with literal when is_list(literal) <- defmodule_literal_segments(defmodule_ast),
         true <- atom_segments?(literal),
         true <- is_list(child_absolute) and atom_segments?(child_absolute),
         target when target != [] <- Enum.drop(child_absolute, -(length(literal) - 1)) do
      define(env, :alias, [], Module.concat(target), [])
    else
      _ -> env
    end
  end

  @doc """
  Resolves a literal `defmodule` name into absolute module segments
  through the visible env.

  When `parent_absolute` is empty, the module is top-level and the
  visible aliases apply to its literal segments. When it is a module
  path, the module is nested, and Elixir resolves it by prepending the
  enclosing path without applying lexical aliases to the nested name
  itself. Returns `nil` when the segments are not a literal alias or the
  enclosing module path is already unknown.
  """
  def absolute_module_segments(literal_segments, parent_absolute, %Macro.Env{} = env)
      when is_list(literal_segments) do
    cond do
      not Enum.all?(literal_segments, &is_atom/1) -> nil
      is_nil(parent_absolute) -> nil
      parent_absolute == [] -> expand_alias(literal_segments, env)
      true -> parent_absolute ++ literal_segments
    end
  end

  def absolute_module_segments(_literal_segments, _parent_absolute, %Macro.Env{}), do: nil

  @doc """
  Expands module alias segments through `env` using the compiler's own
  resolution (`Macro.Env.expand_alias/4`). Segments in, segments out:
  unresolvable input (non-atom segments, no matching alias) is returned
  unchanged.
  """
  def expand_alias(segments, %Macro.Env{} = env) when is_list(segments) do
    with true <- atom_segments?(segments),
         {:alias, module} <- Macro.Env.expand_alias(env, [], segments),
         resolved when is_list(resolved) <- elixir_module_segments(module) do
      resolved
    else
      _ -> segments
    end
  end

  @doc """
  Substitutes `__MODULE__` elements in expanded alias segments with the
  enclosing `defmodule`'s absolute segments (`alias __MODULE__.Post`
  targets carry the raw `__MODULE__` AST tuple). Returns
  `{:ok, segments}` only when every resulting segment is an atom,
  because `Module.concat/1` raises on anything else, and `:error` when
  substitution is impossible (no enclosing literal module) or non-atom
  segments remain.
  """
  def resolve_module_self(segments, enclosing) when is_list(segments) do
    resolved =
      Enum.flat_map(segments, fn
        {:__MODULE__, _, _} when is_list(enclosing) and enclosing != [] -> enclosing
        other -> [other]
      end)

    if Enum.all?(resolved, &is_atom/1), do: {:ok, resolved}, else: :error
  end

  @doc """
  Resolves a module reference (an `__aliases__` node or bare segments)
  through a context map carrying `:env`. Non-reference input is returned
  unchanged.
  """
  def resolved_module_ref({:__aliases__, _meta, segments}, context) do
    resolved_module_ref(segments, context)
  end

  def resolved_module_ref(segments, %{env: %Macro.Env{} = env}) when is_list(segments) do
    expand_alias(segments, env)
  end

  def resolved_module_ref(other, _context), do: other

  # ── Macro.Env directive machinery ──

  # Normalizes a directive AST node into `{kind, meta, target_segments,
  # kind_opts}` tuples. Grouped forms (`alias P.{A, B}`) yield one tuple
  # per suffix; `require`/`import` share the same shapes. Anything else
  # yields no tuples. For `alias`/`require`, `kind_opts` is `[]`,
  # `[as: Module]`, or the `:invalid` marker for a multi-segment `as:`
  # (invalid Elixir), in which case the whole entry is skipped rather
  # than misregistered under a guessed name. For `import`, it is the
  # literal `only:`/`except:` selection, or `:dynamic` when the selection
  # is not statically analyzable (the import then registers as a plain
  # require).
  defp directive_targets({kind, meta, [target]}) when kind in @directive_kinds do
    directive_targets({kind, meta, [target, []]})
  end

  defp directive_targets({kind, meta, [{:__aliases__, _, segments}, opts]})
       when kind in @directive_kinds and is_list(opts) do
    [{kind, meta, segments, directive_opts(kind, opts)}]
  end

  defp directive_targets({kind, meta, [{{:., _, [prefix, :{}]}, _, suffixes}, opts]})
       when kind in @directive_kinds and is_list(suffixes) and is_list(opts) do
    case grouped_prefix_segments(prefix) do
      nil ->
        []

      prefix_segments ->
        for {:__aliases__, _, suffix_segments} <- suffixes do
          {kind, meta, prefix_segments ++ suffix_segments, grouped_directive_opts(kind, opts)}
        end
    end
  end

  defp directive_targets(_), do: []

  defp directive_opts(:import, opts), do: import_opts(opts)
  defp directive_opts(_kind, opts), do: as_option(opts)

  # Grouped `alias P.{A, B}, as: ...` is invalid Elixir, so alias/require
  # opts are dropped for grouped forms (preserving prior behavior); a
  # grouped import keeps its selection.
  defp grouped_directive_opts(:import, opts), do: import_opts(opts)
  defp grouped_directive_opts(_kind, _opts), do: []

  # Extracts the literal `only:`/`except:` selection from import opts.
  # Returns a keyword of validated selections ([] when none), or
  # `:dynamic` when a selection exists but is not a literal the linter
  # can evaluate (`only: @funs`, `only: some_call()`).
  defp import_opts(opts) do
    opts
    |> Enum.filter(&match?({key, _} when key in [:only, :except], &1))
    |> Enum.reduce_while([], fn {key, value}, acc ->
      case import_selection(value) do
        {:ok, selection} -> {:cont, [{key, selection} | acc]}
        :error -> {:halt, :dynamic}
      end
    end)
  end

  defp import_selection(kind) when kind in [:functions, :macros, :sigils], do: {:ok, kind}

  defp import_selection(list) when is_list(list) do
    if Enum.all?(list, &match?({name, arity} when is_atom(name) and is_integer(arity), &1)) do
      {:ok, list}
    else
      :error
    end
  end

  defp import_selection(_value), do: :error

  defp grouped_prefix_segments({:__aliases__, _, prefix_segments}), do: prefix_segments
  defp grouped_prefix_segments({:__MODULE__, _, _} = self_ref), do: [self_ref]
  defp grouped_prefix_segments(_), do: nil

  defp as_option(opts) do
    case Keyword.get(opts, :as) do
      nil ->
        []

      {:__aliases__, _, [name]} when is_atom(name) and not is_nil(name) ->
        [as: Module.concat([name])]

      {:__aliases__, _, _} ->
        :invalid

      _other ->
        []
    end
  end

  defp apply_target(env, _kind, _meta, _segments, :invalid, _enclosing), do: env

  defp apply_target(env, kind, meta, segments, as_opts, enclosing) do
    with {:ok, substituted} <- substitute_self(segments, enclosing),
         {:ok, module} <- expand_to_module(substituted, env) do
      define(env, kind, meta, module, as_opts)
    else
      _ -> env
    end
  end

  defp substitute_self([{:__MODULE__, _, _} | rest], enclosing)
       when is_list(enclosing) and enclosing != [] do
    {:ok, enclosing ++ rest}
  end

  defp substitute_self([{:__MODULE__, _, _} | _rest], _enclosing), do: :error
  defp substitute_self(segments, _enclosing), do: {:ok, segments}

  defp define(env, :alias, meta, module, as_opts) do
    keep_on_error(env, Macro.Env.define_alias(env, meta, module, as_opts ++ [trace: false]))
  end

  defp define(env, :require, meta, module, as_opts) do
    keep_on_error(env, Macro.Env.define_require(env, meta, module, as_opts ++ [trace: false]))
  end

  # A real import registration needs the module loaded (`define_import`
  # reads its export table and raises otherwise - verified empirically)
  # and a statically known selection. Anything else registers the require
  # the import implies, which is exactly the pre-import-support behavior.
  # A successful `define_import` also marks the module required, so
  # `Macro.Env.required?/2` consumers see the same env either way.
  defp define(env, :import, meta, module, selection) do
    with selection when is_list(selection) <- selection,
         true <- Code.ensure_loaded?(module),
         {:ok, updated} <- try_define_import(env, meta, module, selection) do
      updated
    else
      _ -> keep_on_error(env, Macro.Env.define_require(env, meta, module, trace: false))
    end
  end

  # `define_import` validates the selection against the module's real
  # exports. A stale `only:` naming a function the module no longer
  # exports still returns `{:ok, env}`: the compiler prints a "cannot
  # import" warning (`warn: false` does not silence it), drops the entry,
  # and marks the module required, which is the same end state as the
  # require fallback. Pathological input raises, and the rescue routes it
  # through the with-else above.
  defp try_define_import(env, meta, module, selection) do
    Macro.Env.define_import(env, meta, module, selection ++ [trace: false, warn: false])
  rescue
    _ -> :error
  end

  defp keep_on_error(_env, {:ok, updated}), do: updated
  defp keep_on_error(env, {:error, _}), do: env

  defp atom_segments?(segments) do
    segments != [] and Enum.all?(segments, &(is_atom(&1) and not is_nil(&1)))
  end

  # `Module.split/1` raises for non-Elixir atoms; alias targets extracted
  # from `__aliases__` nodes are always Elixir modules, but stay defensive.
  defp elixir_module_segments(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> module |> Module.split() |> Enum.map(&String.to_atom/1)
      _other -> nil
    end
  end
end
