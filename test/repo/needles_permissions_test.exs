defmodule Bonfire.Common.NeedlesPermissionsTest do
  use Bonfire.Common.DataCase, async: false
  require Bonfire.Common.Config

  alias Bonfire.Common.{Needles, QueryModule, Repo}
  alias Bonfire.Data.Social.PostContent
  alias Bonfire.Me.{Accounts, Fake, Users}

  @moduletag capture_log: true

  setup do
    Process.put([:bonfire, :skip_all_boundary_checks], false)
    refute Bonfire.Common.Config.get(:skip_all_boundary_checks)

    owner = Fake.fake_user!(Fake.fake_account!())
    other = Fake.fake_user!(Fake.fake_account!())
    refute Accounts.is_admin?(owner)
    refute Accounts.is_admin?(other)

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: owner,
        post_attrs: %{post_content: %{html_body: Faker.Lorem.sentence()}},
        boundary: "public"
      )

    # A query module would bypass the generic fallback this regression covers.
    refute match?(%Ecto.Query{}, QueryModule.maybe_query(PostContent, [[id: post.id], []]))

    {:ok, owner: owner, other: other, post: post}
  end

  test "admins option does not grant delete access to another ordinary user", context do
    assert lookup(context.post, context.other, skip_boundary_check: :admins) == nil

    assert %PostContent{id: id} =
             lookup(context.post, context.owner, skip_boundary_check: :admins)

    assert id == context.post.id
  end

  test "admins option allows an instance administrator to load another user's object", context do
    {:ok, admin} = Users.make_admin(context.other)
    assert Accounts.is_admin?(admin)

    assert %PostContent{id: id} = lookup(context.post, admin, skip_boundary_check: :admins)
    assert id == context.post.id
  end

  test "absent and false options retain ordinary permission checks", context do
    for opts <- [[], [skip_boundary_check: false]] do
      assert lookup(context.post, context.other, opts) == nil
      assert %PostContent{id: id} = lookup(context.post, context.owner, opts)
      assert id == context.post.id
    end
  end

  describe "get/2 given an already loaded object" do
    test "returns that same object to a viewer the boundaries allow", context do
      assert {:ok, got} =
               Needles.get(context.post, current_user: context.owner, verbs: [:delete])

      assert got == context.post, "the object passed in comes back as loaded, not re-fetched"
    end

    test "refuses it to a viewer the boundaries refuse, as for its id", context do
      assert {:error, :not_found} =
               Needles.get(context.post.id, current_user: context.other, verbs: [:delete]),
             "control: the id is refused to this viewer"

      assert {:error, :not_found} =
               Needles.get(context.post, current_user: context.other, verbs: [:delete]),
             "holding the loaded object must not get past the check its id gets"
    end

    test "decides the same as its id, for each viewer", context do
      for {user, label} <- [{context.owner, "owner"}, {context.other, "other"}] do
        opts = [current_user: user, verbs: [:delete]]

        assert match?({:ok, _}, Needles.get(context.post.id, opts)) ==
                 match?({:ok, _}, Needles.get(context.post, opts)),
               "the id and the loaded object answer differently for the #{label}"
      end
    end
  end

  defp lookup(post, user, opts) do
    PostContent
    |> Needles.query([id: post.id], Keyword.merge(opts, current_user: user, verbs: [:delete]))
    |> Repo.one()
  end
end
