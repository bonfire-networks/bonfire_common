# Nebulex dependency path
nbx_dep_path = Mix.Project.deps_paths()[:nebulex]
test_path = Path.dirname(__ENV__.file)

if File.exists?("#{nbx_dep_path}/test/") do
  for file <- File.ls!("#{nbx_dep_path}/test/support"), file != "test_cache.ex" do
    Code.require_file("#{nbx_dep_path}/test/support/" <> file, __DIR__)
  end

  for file <- File.ls!("#{nbx_dep_path}/test/shared/cache") do
    Code.require_file("#{nbx_dep_path}/test/shared/cache/" <> file, __DIR__)
  end

  for file <- File.ls!("#{nbx_dep_path}/test/shared"), file != "cache" do
    Code.require_file("#{nbx_dep_path}/test/shared/" <> file, __DIR__)
  end

  # # Load shared tests
  # for file <- File.ls!("#{test_path}/cache_support"),
  #     not File.dir?("#{test_path}/cache_support/" <> file) do
  #   Code.require_file("#{test_path}/cache_support/" <> file, __DIR__)
  # end
else
  IO.warn("You need to clone the nebulex dep to run its tests")
end
