defmodule Bonfire.Common.BehaviourModulesInferredTest do
  @moduledoc """
  `SchemaModule`, `ContextModule` and `QueryModule` each declare all three callbacks, so a module registered under any one of them can name its counterparts. `modules/0` only ever returned modules that *declared* that behaviour, which meant `SchemaModule.modules/0` listed a handful while dozens of context modules pointed at schemas it never mentioned.

  `modules_inferred/0` adds what the other two point at, and `modules_all/0` is the union. `modules/0` is left alone so existing callers are unaffected.
  """
  use Bonfire.Common.DataCase, async: false

  alias Bonfire.Common.SchemaModule
  alias Bonfire.Common.ContextModule
  alias Bonfire.Common.QueryModule

  describe "SchemaModule" do
    test "modules/0 keeps returning only modules that declare the behaviour" do
      declared = SchemaModule.modules()

      assert Bonfire.Classify.Category in declared

      # guards the premise: if these ever start declaring the behaviour, the inferred lookup below
      # stops proving anything
      refute Bonfire.Data.Social.Post in declared
      refute Bonfire.Data.Identity.User in declared
    end

    test "modules_inferred/0 returns schemas that context and query modules point at" do
      inferred = SchemaModule.modules_inferred()

      assert Bonfire.Data.Social.Post in inferred
      assert Bonfire.Data.Identity.User in inferred
    end

    test "modules_inferred/0 returns the pointed-at schemas, not the modules pointing at them" do
      # `apply_modules/2` caches both directions, so a naive `Map.keys/1` would include contexts
      inferred = SchemaModule.modules_inferred()

      refute Bonfire.Posts in inferred
      refute Bonfire.Me.Users in inferred
    end

    test "modules_all/0 is the union, without duplicates" do
      all = SchemaModule.modules_all()

      assert Bonfire.Classify.Category in all
      assert Bonfire.Data.Social.Post in all
      assert all == Enum.uniq(all)
    end
  end

  describe "ContextModule" do
    test "modules_all/0 includes contexts inferred from the other two behaviours" do
      all = ContextModule.modules_all()

      assert Bonfire.Posts in all
      assert Bonfire.Me.Users in all
      assert all == Enum.uniq(all)
    end
  end

  describe "QueryModule" do
    test "modules_all/0 includes queries inferred from the other two behaviours" do
      all = QueryModule.modules_all()

      assert all == Enum.uniq(all)
      assert length(all) >= length(QueryModule.modules())
    end
  end

  describe "object type names" do
    test "cover the schemas that context modules declare" do
      names = Bonfire.Common.Types.all_object_type_names()

      assert "post" in names
      assert "user" in names
      assert "message" in names
      assert "Delete this post" in names
    end
  end
end
