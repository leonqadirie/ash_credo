import Config

# Ash refuses to compile any resource in the root project unless this key is
# set. Only the test fixtures define resources, so scope it to :test. Consuming
# projects never load a library's config files.
if config_env() == :test do
  config :ash, default_string_length_count: :codepoints
end
