class TermsDictionary < ActiveRecord::Base
  acts_as_copy_target
  audited

  include Audit

  validates :presence_identifier_character, presence: true, length: { is: 1 }

  def self.current
    self.first || new
  end

  def self.cached_current
    Rails.cache.fetch("#{EntitySingletoon.current.id}_current_terms_dictionary", expires_in: 10.minutes) do
      self.current
    end
  end
end
