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

  defp lookup(post, user, opts) do
    PostContent
    |> Needles.query([id: post.id], Keyword.merge(opts, current_user: user, verbs: [:delete]))
    |> Repo.one()
  end
end
