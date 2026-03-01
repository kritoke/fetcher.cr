module Fetcher
  record RequestConfig,
    connect_timeout : Time::Span = 10.seconds,
    read_timeout : Time::Span = 30.seconds,
    max_redirects : Int32 = 5,
    follow_redirects : Bool = true,
    ssl_verify : Bool = true
end
