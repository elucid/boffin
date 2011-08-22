module Boffin
  class Tracker

    attr_reader :config, :ks

    def initialize(config = Boffin.config.dup)
      @config = config
      @ks = Keyspace.new(@config)
    end

    def hit(ns, thing, hit_type, uniquenesses = [], opts = {})
      Hit.new(self, ns, hit_type, thing, uniquenesses, opts)

      now     = Time.now
      umember = uniquenesses_as_member(uniquenesses, opts[:unique])
      key     = object_as_key(thing)
      if track_hit(ns, key, hit_type, umember)
        store_windows(now, ns, thing, hit_type, true)
      else
        store_windows(now, ns, thing, hit_type, false)
      end
    end

    def uhit(*args)
      if args.last.is_a?(Hash)
        args.last[:unique] = true
      else
        args.push(unique: true)
      end
      hit(*args)
    end

    def hit_count(ns, thing, type)
      key = object_as_key(thing)
      rdb.get(@ks.object_hit_count_key(ns, key, type)).to_i
    end

    def uhit_count(ns, thing, type)
      key = object_as_key(thing)
      rdb.scard(@ks.object_hits_key(ns, key, type)).to_i
    end

    def top(ns, type, params = {})
      unit, size = *Utils.extract_time_unit(params)
      storkey    = @ks.hits_union_key(ns, type, unit, size)
      keys       = window_keys(ns, type, unit, size)
      fetch_zunion(storkey, keys, params)
    end

    def utop(ns, type, params = {})
      warn('utop')
      top("#{ns}.uniq", params)
    end

    def trending(ns, params = {})
      unit, size = *Utils.extract_time_unit(params)
      hit_types  = weights.keys
      weights    = params[:weights]
      keys       = hit_types.map { |t| window_keys(ns, type, unit, t) }
      storkey    = @ks.combi_hits_union_key(ns, weights, unit, size)
      opts       = { weights: weights.values }.merge(params)
      types.each { top(ns, type, params) }
      fetch_zunion(storkey, keys, opts)
    end

    def utrending(ns, params = {})
      warn('utrending')
      trending("#{ns}.uniq", params)
    end

    private

    def rdb
      @config.redis
    end

    def track_hit(ns, key, hit_type, umember)
      rdb.incr(@ks.object_hit_count_key(ns, key, hit_type))
      rdb.zincrby(@ks.object_hits_key(ns, key, hit_type), 1, umember).to_i == 1
    end

    def store_windows(time, ns, thing, hit_type, is_unique)
      member = object_as_member(thing)
      WINDOW_UNIT_TYPES.each do |window|
        sec = @config.send("#{window}_window_secs")
        key = @ks.hits_time_window_key(ns, hit_type, window, time)
        if is_unique && !@config.disable_unique_tracking
          ukey = @ks.hits_time_window_key("#{ns}.uniq", hit_type, window, time)
          rdb.zincrby(ukey, 1, member)
          rdb.expire(ukey, member)
        end
        rdb.zincrby(key, 1, member)
        rdb.expire(key, member)
      end
    end

    def object_as_member(obj)
      @config.object_as_member_proc.(obj)
    end

    def uniquenesses_as_member(uniquenesses, ensure_not_nil = false)
      case
      when (obj = uniquenesses.flatten.reject { |u| Utils.blank?(u) }.first)
        if obj.respond_to?(:id)
          "#{Utils.underscore(obj.class)}:#{obj.id}"
        else
          obj.to_s
        end
      when ensure_not_nil
        raise NoUniquenessError, 'Unique criteria not provided for the ' \
        'incoming hit.'
      else
        Utils.quick_token
      end
    end

    def fetch_zunion(storekey, keys, opts = {})
      zrangeopts = {
        counts: opts.delete(:counts),
        order:  (opts.delete(:order) || :desc).to_sym }
      if rdb.zcard(storekey) == 0 # Not cached, or has expired
        rdb.zunionstore(storekey, keys, opts)
        rdb.expire(storekey, @config.cache_expire_secs)
      end
      zrange(storekey, zrangeopts)
    end

    def zrange(key, opts)
      cmdopt = opts[:counts] ? { withscores: true } : {}
      args   = [key, 0, -1, cmdopt]
      result = case opts[:order]
        when :asc  then rdb.zrange(*args)
        when :desc then rdb.zrevrange(*args)
      end
      if opts[:counts]
        result.each_slice(2).map { |mbr, score| [mbr, score.to_i] }
      else
        result
      end
    end

    def warn(method)
      return if @config.enable_unique_tracking
      STDERR.puts("Warning: Tracker##{method} was called but unique tracking " \
      "is disabled.")
    end

  end
end
