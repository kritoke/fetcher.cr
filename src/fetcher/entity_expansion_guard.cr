require "./exceptions"

module Fetcher
  # Shared module for XXE and entity expansion protection.
  # Provides consistent security checks across DOM and streaming parsers.
  module EntityExpansionGuard
    # Perform all entity expansion checks on content
    def self.check(content : String, max_entities : Int32 = MAX_ENTITY_DEFINITIONS) : Nil
      upper = content.upcase

      # Reject DOCTYPE with internal subset - common vector for entity expansion attacks
      if upper.includes?("<!DOCTYPE") && upper.includes?("[")
        raise InvalidFormatError.new("DOCTYPE with internal subset not allowed (entity expansion risk)")
      end

      # Check for parameter entities which are also dangerous
      if upper.scan(/<!ENTITY\s+%/i).size > 0
        raise InvalidFormatError.new("Parameter entity declarations not allowed")
      end

      # Check for external entity declarations (SYSTEM keyword)
      if upper.includes?("<!ENTITY") && upper.includes?("SYSTEM")
        raise InvalidFormatError.new("External entity declarations not allowed")
      end

      # Check entity definition count
      entity_count = count_entity_definitions(content)
      if entity_count > max_entities
        raise InvalidFormatError.new("Too many entity definitions (#{entity_count})")
      end
    rescue ex : InvalidFormatError
      raise ex
    rescue
      # Ignore unexpected errors during the check (e.g., regex failures)
    end

    # Count ENTITY definitions in content
    def self.count_entity_definitions(content : String) : Int32
      count = 0
      content.scan(/<!ENTITY\s+\w+\s+[^>]*>/i) { count += 1 }
      count
    end
  end
end