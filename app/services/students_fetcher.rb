class StudentsFetcher
  def initialize(ieducar_api_configuration, classroom_api_code, discipline_api_code = nil, date = Time.zone.today)
    @ieducar_api_configuration = ieducar_api_configuration
    @classroom_api_code = classroom_api_code
    @discipline_api_code = discipline_api_code
    @date = date
  end

  def fetch
    api = IeducarApi::Students.new(@ieducar_api_configuration.to_api)
    result = api.fetch_for_daily(
      {
        classroom_api_code: @classroom_api_code,
        discipline_api_code: @discipline_api_code,
        date: @date
      }
    )
    api_students = result['alunos']
    students_api_codes = api_students.map { |api_student| api_student['id'] }

    Student.where(api_code: students_api_codes).ordered
  end
end
