defmodule Bonfire.Common.ImportDispatchTest do
  use Bonfire.Common.DataCase, async: true

  @moduletag :backend

  alias Bonfire.Common.Import

  test "a job whose op no extension handles fails, rather than reporting success" do
    assert {:error, _} =
             Import.perform(%Oban.Job{
               args: %{
                 "op" => "no_such_import_op",
                 "user_id" => "instance_wide",
                 "identifier" => "someone@example.local"
               }
             })
  end

  test "an op is handled by the extension that declares it" do
    assert Import.op_handler("no_such_import_op") == nil
  end

  test "each list op is handled by the extension that owns what it does" do
    for op <- ["follows_import", "likes_import", "boosts_import", "bookmarks_import"] do
      assert Import.op_handler(op) == Bonfire.Social.ImportOps, "#{op}"
    end

    for op <- ["blocks_import", "silences_import", "ghosts_import", "circles_import"] do
      assert Import.op_handler(op) == Bonfire.Boundaries.ImportOps, "#{op}"
    end

    # the outbox ops are with the ActivityPub archive handling
    assert Import.op_handler("outbox_creations_import") ==
             Bonfire.Federate.ActivityPub.Import.OutboxOps
  end

  test "an op's label comes from the extension that handles it" do
    assert Import.op_label("follows_import") == "Follow"
    assert Import.op_label("blocks_import") == "Block"
  end

  test "the job preparing an import, which the framework does itself, has a label and a phrase" do
    assert Import.op_label("import_materialize") == "Preparing import"
    assert Import.op_phrase("import_materialize") == "Preparing import"
  end

  test "the sources a file can be staged from are found among the extensions, not registered in config" do
    # with nothing in config, as no extension should need to register a source there
    Process.put([:bonfire_common, Bonfire.Common.Import, :archive_sources], [])

    sources = Import.archive_sources()

    # other extensions' sources (eg. WordPress's) are checked in their own tests, since not every flavour includes them
    assert sources[:archive] == Bonfire.Federate.ActivityPub.Import.Archive

    # a form sends the key as a string, matched without making an atom
    assert Import.archive_source("archive") == Bonfire.Federate.ActivityPub.Import.Archive
    assert Import.archive_source("not_a_source") == nil
  end
end
