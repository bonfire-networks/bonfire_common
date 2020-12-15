defmodule Bonfire.Config do
  def has_extension_config?(lib) do
    if !Application.get_env(lib, :env) do
      IO.warn(
        "ERROR: You have not configured this Bonfire extension, please copy ./deps/#{lib}/config/#{
          lib
        }.ex to ./config/#{lib}.ex in your Bonfire app repository, and then customise it as necessary and add a line with `import_config \"#{
          lib
        }.exs\"` to your ./config/config.ex"
      )

      false
    else
      true
    end
  end
end
