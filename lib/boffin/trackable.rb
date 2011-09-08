module Boffin
  # Can be included into a class that responds to `#as_member`, `#to_i`, or
  # `#to_s`. It's recommended to use {Boffin.track} to inject Trackable into a
  # class. It provides the instance methods of Tracker scoped to the host class
  # and its instances.
  #
  # @example
  #   class MyModel < ActiveRecord::Base
  #     include Boffin::Trackable
  #     boffin.hit_types = [:views, :likes]
  #   end
  #
  #   # Then record hits to instances of your model
  #   @my_model = MyModel.find(1)
  #   @my_model.hit(:views)
  #
  # See {file:README} for more examples.
  module Trackable

    # @private
    def self.included(mod)
      mod.extend(ClassMethods)
    end

    # Included as class methods in the host class
    module ClassMethods
      # @return [Tracker] The Tracker instance associated with the class
      def boffin
        @boffin ||= ::Boffin::Tracker.new(self)
      end

      # @param [Symbol, Hash] type_or_weights
      # @param [Hash] opts
      # @return [Array<String>, Array<Array>]
      # @see Tracker#top
      def top_ids(type_or_weights, opts = {})
        boffin.top(type_or_weights, opts)
      end
    end

    # @see Tracker#hit
    # @return [Hit]
    def hit(type, uniquenesses = [])
      self.class.boffin.hit(type, self, uniquenesses)
    end

    # @see Tracker#hit_by
    # @return [HitBy]
    def hit_by(increment, type, uniquenesses = [])
      self.class.boffin.hit_by(increment, type, self, uniquenesses)
    end

    # @see Tracker#hit_count
    # @return [Fixnum]
    def hit_count(type)
      self.class.boffin.hit_count(type, self)
    end

    # @see Tracker#uhit_count
    # @return [Fixnum]
    def uhit_count(type)
      self.class.boffin.uhit_count(type, self)
    end

    # @see Tracker#hit_count_for_session_id
    # @return [Fixnum]
    def hit_count_for_session_id(type, sess_obj)
      self.class.boffin.hit_count_for_session_id(type, self, sess_obj)
    end

  end
end
