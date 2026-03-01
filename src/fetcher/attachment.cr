module Fetcher
  record Attachment,
    url : String,
    mime_type : String,
    title : String? = nil,
    size_in_bytes : Int64? = nil,
    duration_in_seconds : Int32? = nil
end
