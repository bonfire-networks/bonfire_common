defmodule Bonfire.Common.Repo.PreloadRecoveryTest do
  @moduledoc """
  When one preload in a list is invalid (e.g. a heterogeneous list where an object type lacks an
  association), `Repo.preload` raises for the WHOLE call. `maybe_preload` recovers by pruning the
  invalid (sub-)entries via schema reflection and preloading the valid rest in one call (the
  long-standing TODO in `try_repo_preload`).

  By default the crash is reported via `err` — which raises in test env so the bad preload list
  gets fixed at its source; these tests pass `skip_err: true` to exercise the recovery path itself.
  """
  use Bonfire.Common.DataCase, async: false

  alias Bonfire.Common.Repo.Preload
  alias Bonfire.Data.Identity.User
  alias Bonfire.Data.Identity.Character

  setup do
    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)

    # `fake_user!` returns the user with `:character` (and `character.peered`) already preloaded, so
    # re-fetch a fresh copy where associations are NOT loaded — otherwise the assertions below would
    # pass trivially without ever exercising the recovery path.
    {:ok, user: Bonfire.Common.Repo.get!(User, user.id)}
  end

  test "recovers from an invalid top-level preload and still loads the valid ones", %{user: user} do
    # correctness guard: the assoc really isn't loaded before we preload, so a pass means recovery worked
    assert match?(%Ecto.Association.NotLoaded{}, user.character)

    # `:character` is valid; `:this_assoc_does_not_exist` makes a single `Repo.preload` raise
    preloaded =
      Preload.maybe_preload(user, [:character, :this_assoc_does_not_exist], skip_err: true)

    # the valid assoc must still be loaded (not dropped because the batch preload raised)
    assert %Character{} = preloaded.character
  end

  test "recovers from an invalid NESTED sub-entry, keeping the valid nested ones", %{user: user} do
    # `:peered` under `:character` is valid; the bogus sibling makes the whole `{:character, [...]}`
    # entry raise — recovery must drop only the bad sub-entry, keeping `:character` and its `:peered`
    preloaded =
      Preload.maybe_preload(user, [character: [:peered, :this_nested_does_not_exist]],
        skip_err: true
      )

    assert %Character{} = preloaded.character
    refute match?(%Ecto.Association.NotLoaded{}, preloaded.character.peered)
  end

  test "recovers from an invalid DEEP nested sub-entry, keeping the valid nested ones", %{
    user: user
  } do
    # the invalid part is two levels down (`character.peered.<bogus>`); recovery must recurse and
    # drop only that, keeping `character` and `character.peered`
    preloaded =
      Preload.maybe_preload(user, [character: [peered: [:this_nested_does_not_exist]]],
        skip_err: true
      )

    assert %Character{} = preloaded.character
    refute match?(%Ecto.Association.NotLoaded{}, preloaded.character.peered)
  end
end
