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

  test "prune: true fits a superset preload list to the schema upfront (reflection, no raise)", %{
    user: user
  } do
    # for call sites whose preload list is a deliberate superset across possible schemas (e.g.
    # `AdapterUtils.get_character`): `prune: true` drops assocs the actual schema lacks BEFORE
    # preloading, so nothing raises (not even in test env) and the valid ones load
    assert match?(%Ecto.Association.NotLoaded{}, user.character)

    preloaded =
      Preload.maybe_preload(user, [:character, :this_assoc_does_not_exist], prune: true)

    assert %Character{} = preloaded.character
  end

  test "prune: true on a heterogeneous list splits per schema proactively (no recovery round-trip)",
       %{user: user} do
    # prune + mixed list must go straight to the per-schema path: pruned to each schema's own
    # assocs (NOT the intersection, which could silently drop everything) and batched without
    # ever hitting the raise-and-recover machinery (no "batch preload raised" log)
    {:ok, pointer} = Bonfire.Common.Needles.one(user.id, skip_boundary_check: true)

    {result, log} =
      ExUnit.CaptureLog.with_log(fn ->
        Preload.maybe_preload([user, pointer], [:character], prune: true)
      end)

    assert [%User{} = u, %Needle.Pointer{} = p] = result
    assert %Character{} = u.character
    assert %Character{} = p.character
    refute log =~ "batch preload raised"
  end

  test "recovers a HETEROGENEOUS list by batching per schema, preserving order", %{user: user} do
    # a mixed-struct list makes `Repo.preload` raise outright ("expected a homogeneous list"),
    # regardless of assoc validity — recovery must split per schema and reassemble in order
    {:ok, pointer} = Bonfire.Common.Needles.one(user.id, skip_boundary_check: true)

    assert match?(%Ecto.Association.NotLoaded{}, user.character)
    assert match?(%Ecto.Association.NotLoaded{}, pointer.character)

    assert [%User{} = u, %Needle.Pointer{} = p] =
             Preload.maybe_preload([user, pointer], :character, skip_err: true)

    assert %Character{} = u.character
    assert %Character{} = p.character
  end

  test "a heterogeneous list WITHOUT prune/skip_err raises in test env (fix-at-source signal)", %{
    user: user
  } do
    # a mixed-struct list hitting the raise-and-recover path is a source bug like any other: the
    # call site should declare `prune: true` (proactive per-schema path). `err` raises in test
    # env so it gets annotated there rather than leaning on silent recovery.
    {:ok, pointer} = Bonfire.Common.Needles.one(user.id, skip_boundary_check: true)

    assert_raise RuntimeError, ~r/batch preload raised/, fn ->
      Preload.maybe_preload([user, pointer], :character)
    end
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
