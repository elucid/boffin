module Boffin
  # Immutable Hit instance with custom increment
  class HitBy < Hit
    # Creates a new Hit instance with specified increment
    #
    # @param [Fixnum] increment
    #   Amount to increment the hit by. Must be an integer.
    # @param [Tracker] tracker
    #   Tracker that is issuing the hit
    # @param [Symbol] type
    #   Hit type identifier
    # @param [Object] instance
    #   The instance that is being hit, any object that responds to
    #   `#to_member`, `#id`, or `#to_s`
    # @param [Array] uniquenesses
    #   An array of which the first object is used to generate a session
    #   identifier for hit uniqueness
    def initialize(increment, tracker, type, instance, uniquenesses = [])
      @increment = increment
      super tracker, type, instance, uniquenesses
    end

    # Increments the {Keyspace#hit_count} key by increment and adds the
    # session member to {Keyspace#hits}.
    # @return [true, false]
    #   `true` if this hit is unique, `false` if it has been made before by the
    #   same session identifer.
    def track_hit
      redis.incrby(keyspace.hit_count(@type, @instance), @increment)
      redis.zincrby(keyspace.hits(@type, @instance), 1, @sessid) == '1'
    end

    # Increments in the instance member in the sorted set under
    # {Keyspace#hits_time_window} by increment
    # @param [:hours, :days, :months] interval
    # @param [true, false] uniq
    #   Changes keyspace scope to keys under .uniq
    def set_window_interval(interval, uniq = false)
      key = keyspace(uniq).hits_time_window(@type, interval, @now)
      redis.zincrby(key, @increment, @member)
      redis.expire(key, @tracker.config.send("#{interval}_window_secs"))
    end

  end
end
