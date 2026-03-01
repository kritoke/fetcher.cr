module Fetcher
  record Result,
    entries : Array(Entry),
    etag : String?,
    last_modified : String?,
    site_link : String?,
    favicon : String?,
    error_message : String? do
    def self.error(message : String) : Result
      new(entries: [] of Entry, etag: nil, last_modified: nil,
        site_link: nil, favicon: nil, error_message: message)
    end

    def self.success(entries : Array(Entry),
                     etag : String? = nil,
                     last_modified : String? = nil,
                     site_link : String? = nil,
                     favicon : String? = nil) : Result
      new(entries: entries, etag: etag, last_modified: last_modified,
        site_link: site_link, favicon: favicon, error_message: nil)
    end
  end
end
