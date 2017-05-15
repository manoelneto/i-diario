class RecoverySchoolCalendarClassroomStepsFetcher
  def initialize(school_calendar_classroom_step_id, classroom_id)
    @school_calendar_classroom_step_id = school_calendar_classroom_step_id
    @classroom_id = classroom_id
  end

  def fetch
    school_calendar_classroom_steps = []
    if recovery_exam_rule
      school_calendar_classroom_steps = school_calendar_classroom_step.school_calendar_classroom
        .classroom_steps
        .select do |school_calendar_classroom_step|
          recovery_exam_rule.steps.include?(school_calendar_classroom_step.to_number)
        end
    end

    school_calendar_classroom_steps << school_calendar_classroom_step if school_calendar_classroom_steps.empty?

    school_calendar_classroom_steps
  end

  private

  def school_calendar_classroom_step
    SchoolCalendarClassroomStep.find(@school_calendar_classroom_step_id)
  end

  def classroom
    Classroom.find(@classroom_id)
  end

  def recovery_type
    classroom.exam_rule.recovery_type
  end

  def recovery_exam_rule
    classroom.exam_rule.recovery_exam_rules.find do |recovery_diary_record|
      recovery_diary_record.steps.last.eql?(school_calendar_classroom_step.to_number)
    end
  end
end