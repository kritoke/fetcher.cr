module Fetcher
  record RequestConfig,
    connect_timeout : Time::Span = 10.seconds,
    read_timeout : Time::Span = 30.seconds,
    max_requests_per_second : Int32? = nil,
    max_concurrent_requests : Int32? = nil
end
