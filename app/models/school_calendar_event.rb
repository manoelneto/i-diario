class SchoolCalendarEvent < ActiveRecord::Base
  acts_as_copy_target

  audited
  has_associated_audits

  include Audit

  attr_accessor :course_id

  belongs_to :school_calendar
  belongs_to :grade
  belongs_to :classroom
  has_one :course, through: :grade
  delegate :unity_id, to: :school_calendar

  has_enumeration_for :event_type, with: EventTypes
  has_enumeration_for :coverage, with: EventCoverageType

  validates :description, :event_type, :event_date, :school_calendar_id, presence: true
  validates :periods, presence: true, if: :coverage_by_classroom?
  validates :grade, presence: true, if: :should_validate_grade?
  validates :classroom, presence: true, if: :should_validate_classroom?
  validates :legend, presence: true, exclusion: {in: %w(F f N n .) }, if: :should_validate_legend?
  validate :uniquenesss_of_event_in_grade
  validate :uniquenesss_of_event_in_classroom

  scope :ordered, -> { order(arel_table[:event_date]) }
  scope :with_frequency, -> { where(arel_table[:event_type].eq(EventTypes::EXTRA_SCHOOL)) }
  scope :without_frequency, -> { where(arel_table[:event_type].not_eq(EventTypes::EXTRA_SCHOOL)) }
  scope :extra_school_without_frequency, -> { where(event_type: EventTypes::EXTRA_SCHOOL_WITHOUT_FREQUENCY) }
  scope :without_grade, -> { where(arel_table[:grade_id].eq(nil) ) }
  scope :without_classroom, -> { where(arel_table[:classroom_id].eq(nil) ) }
  scope :by_period, lambda { |period| where(' ? = ANY (periods)', period) }
  scope :by_date, lambda { |date| where(event_date: date.to_date) }
  scope :by_date_between, lambda { |start_at, end_at| where(event_date: start_at.to_date..end_at.to_date) }
  scope :by_description, lambda { |description| where('description ILIKE ?', '%'+description+'%') }
  scope :by_type, lambda { |type| where(event_type: type) }
  scope :by_grade, lambda { |grade| where(grade_id: grade) }
  scope :by_classroom, lambda { |classroom| joins(:classroom).where('classrooms.description ILIKE ?', '%'+classroom+'%') }
  scope :by_classroom_id, lambda { |classroom_id| where(classroom_id: classroom_id) }
  scope :all_events_for_classroom, lambda { |classroom| all_events_for_classroom(classroom) }

  def to_s
    description
  end

  def periods=(periods)
    write_attribute(:periods, periods ? periods.split(',').sort : periods)
  end

  def coverage_by_unity?
    self.coverage == EventCoverageType::BY_UNITY
  end

  def coverage_by_classroom?
    self.coverage == EventCoverageType::BY_CLASSROOM
  end

  protected

  def self.all_events_for_classroom(classroom)
    where('? = ANY (periods) OR classroom_id = ?', classroom.period, classroom.id).
    where('grade_id IS NULL OR grade_id = ?', classroom.grade.id).
    where(' "school_calendar_events"."id" in (
            SELECT id
            FROM school_calendar_events sce
            WHERE sce.event_date = "school_calendar_events"."event_date"
            AND sce.school_calendar_id = "school_calendar_events"."school_calendar_id"
            AND (? = ANY (periods) OR classroom_id = ?)
            AND (grade_id IS NULL OR grade_id = ?)
            ORDER BY classroom_id DESC
            LIMIT 1
            )', classroom.period, classroom.id, classroom.grade.id)
  end

  def should_validate_grade?
    [EventCoverageType::BY_GRADE, EventCoverageType::BY_CLASSROOM].include? self.coverage
  end

  def should_validate_classroom?
    self.coverage_by_classroom?
  end

  def should_validate_legend?
    self.event_type != EventTypes::EXTRA_SCHOOL
  end

  def uniquenesss_of_event_in_grade
    return unless event_type && event_date && grade && coverage == EventCoverageType::BY_GRADE
    query = school_calendar.events.where(self.class.arel_table[:event_type].not_eq(self.event_type))
    query = query.where(event_date: self.event_date)
    query = query.where(grade_id: self.grade_id)
    query = query.where(classroom_id: nil)
    errors.add(:event_date, :already_exists_event_in_this_date) if query.any?
  end

  def uniquenesss_of_event_in_classroom
    return unless event_type && event_date && classroom && coverage == EventCoverageType::BY_CLASSROOM
    query = school_calendar.events.where(self.class.arel_table[:event_type].not_eq(self.event_type))
    query = query.where(event_date: self.event_date)
    query = query.where(classroom_id: self.classroom_id)
    errors.add(:event_date, :already_exists_event_in_this_date) if query.any?
  end
end
