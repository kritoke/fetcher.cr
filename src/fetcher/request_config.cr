module Fetcher
  # Configuration for HTTP requests
  #
  # NOTE: Only connect_timeout and read_timeout are currently implemented.
  # max_redirects, follow_redirects, and ssl_verify are reserved for future implementation.
  # See SPEC-003 for details.
  record RequestConfig,
    connect_timeout : Time::Span = 10.seconds,
    read_timeout : Time::Span = 30.seconds
end
