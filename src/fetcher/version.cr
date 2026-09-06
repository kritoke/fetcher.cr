module Fetcher
  # Single source of truth for the library version. Must be kept in sync
  # with `version` in `shard.yml`. Used in User-Agent strings so that
  # upstream services can identify the client version.
  VERSION = "0.9.23"
end
