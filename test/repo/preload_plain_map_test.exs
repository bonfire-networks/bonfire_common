defmodule Bonfire.Common.Repo.PreloadPlainMapTest do
  @moduledoc """
  An association field that already holds a plain map (as ValueFlows puts its agent maps in `creator` or an activity's `subject`) counts as loaded: `maybe_preload` leaves it as it is and preloads the rest, instead of handing it to Ecto, whose preloader accepts only a struct there.
  """
  use Bonfire.Common.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Common.Repo
  alias Bonfire.Me.Fake

  setup do
    user = Fake.fake_user!()

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: user,
        post_attrs: %{post_content: %{html_body: "a post"}},
        boundary: "public"
      )

    agent = %{id: user.id, name: "someone", agent_type: :person}

    activity = %{
      Repo.preload(post.activity, [])
      | subject: agent,
        verb: %Ecto.Association.NotLoaded{}
    }

    {:ok, activity: activity, agent: agent}
  end

  test "a single struct keeps the plain map and preloads the other associations",
       %{activity: activity, agent: agent} do
    preloaded = Repo.maybe_preload(activity, [:subject, :verb])

    assert preloaded.subject == agent
    assert %Bonfire.Data.AccessControl.Verb{} = preloaded.verb
  end

  test "in a list, the object holding the plain map keeps it and the others are preloaded",
       %{activity: activity, agent: agent} do
    other = Fake.fake_user!()

    {:ok, other_post} =
      Bonfire.Posts.publish(
        current_user: other,
        post_attrs: %{post_content: %{html_body: "another post"}},
        boundary: "public"
      )

    [first, second] = Repo.maybe_preload([activity, other_post.activity], [:subject, :verb])

    assert first.subject == agent
    assert %Bonfire.Data.AccessControl.Verb{} = first.verb
    assert second.subject.id == other.id
    assert %Bonfire.Data.AccessControl.Verb{} = second.verb
  end
end
