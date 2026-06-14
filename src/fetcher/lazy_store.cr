# Generates the lazy-init class-level store pattern:
#   @@store : StoreType? = nil
#   @@store_lock = Mutex.new
#   def self.store : StoreType
#     @@store_lock.synchronize { @@store ||= StoreType.new }
#   end
#
# Parameters:
#   store_type  - the store class (e.g. RateLimiterStore)
#   var_name    - the class variable name (default: "store")
#   method_name - the accessor method name (default: "store")
#
# For modules that use `extend self`, write the pattern directly
# (the macro generates `def self.method_name` which doesn't apply).
macro lazy_store(store_type, var_name = "store", method_name = "store")
  @@{{ var_name.id }} : {{ store_type }}? = nil
  @@{{ var_name.id }}_lock = Mutex.new

  def self.{{ method_name.id }} : {{ store_type }}
    @@{{ var_name.id }}_lock.synchronize { @@{{ var_name.id }} ||= {{ store_type }}.new }
  end
end
