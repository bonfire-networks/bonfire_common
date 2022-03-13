defmodule Bonfire.Common.Web.LazyImage do
  use Bonfire.Web, :stateless_component

  prop src, :string
  prop class, :string
  prop alt, :string
  prop opts, :list


end
