module Fetcher
  enum SourceType
    RSS
    Atom
    JSONFeed
    Reddit
    GitHub
    GitLab
    Codeberg
    YouTube

    def to_s : String
      super.downcase
    end

    def self.from_string(value : String) : SourceType
      case value.downcase
      when "rss"                   then RSS
      when "atom"                  then Atom
      when "jsonfeed", "json_feed" then JSONFeed
      when "reddit"                then Reddit
      when "github"                then GitHub
      when "gitlab"                then GitLab
      when "codeberg"              then Codeberg
      when "youtube"               then YouTube
      else                              RSS
      end
    end
  end
end
