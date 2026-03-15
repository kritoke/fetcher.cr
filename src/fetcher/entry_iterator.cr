require "./entry"

module Fetcher
  # Lazy iterator for streaming feed entries
  abstract class EntryIterator
    include Iterator(Entry)

    protected getter finished : Bool = false

    def initialize
    end

    def next
      if @finished
        stop
      else
        entry = next_entry
        if entry
          entry
        else
          @finished = true
          stop
        end
      end
    end

    protected abstract def next_entry : Entry?

    # Convert iterator to array with optional limit
    def to_a(limit : Int32? = nil) : Array(Entry)
      entries = [] of Entry
      count = 0
      while !limit || count < limit
        begin
          entry = self.next
          entries << entry
          count += 1
        rescue Iterator::Stop
          break
        end
      end
      entries
    end
  end
end
