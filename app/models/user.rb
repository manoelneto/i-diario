class User < ActiveRecord::Base
  acts_as_copy_target

  audited allow_mass_assignment: true,
    only: [:email, :first_name, :last_name, :phone, :cpf, :login,
           :authorize_email_and_sms, :student_id, :status, :encrypted_password,
           :teacher_id, :assumed_teacher_id, :current_unity_id, :current_classroom_id,
           :current_discipline_id, :current_school_year, :current_user_role_id]
  has_associated_audits

  include Audit
  include Filterable

  devise :database_authenticatable, :recoverable, :rememberable,
    :trackable, :validatable, :lockable

  attr_accessor :credentials, :has_to_validate_receive_news_fields

  has_enumeration_for :kind, with: RoleKind, create_helpers: true
  has_enumeration_for :status, with: UserStatus, create_helpers: true

  before_destroy :ensure_has_no_audits
  before_validation :verify_receive_news_fields

  belongs_to :student
  belongs_to :teacher
  belongs_to :current_user_role, class_name: 'UserRole'

  has_many :logins, class_name: "UserLogin", dependent: :destroy
  has_many :synchronizations, class_name: "IeducarApiSynchronization", foreign_key: :author_id, dependent: :restrict_with_error

  has_many :system_notification_targets, dependent: :destroy
  has_many :system_notifications, -> { includes(:source) }, through: :system_notification_targets, source: :system_notification
  has_many :unread_notifications, -> { joins(:targets).where(system_notification_targets: { read: false}) },
    through: :system_notification_targets, source: :system_notification

  has_many :ieducar_api_exam_postings, class_name: "IeducarApiExamPosting", foreign_key: :author_id, dependent: :restrict_with_error

  has_and_belongs_to_many :students, dependent: :restrict_with_error

  has_many :user_roles, -> { includes(:role) }, dependent: :destroy

  accepts_nested_attributes_for :user_roles, reject_if: :all_blank, allow_destroy: true

  validates :cpf, mask: { with: "999.999.999-99", message: :incorrect_format }, allow_blank: true, uniqueness: { case_sensitive: false }
  validates :phone, format: { with: /\A\([0-9]{2}\)\ [0-9]{8,9}\z/i }, allow_blank: true
  validates :email, email: true, allow_blank: true
  validates :password, length: { minimum: 8 }, allow_blank: true
  validates :login, uniqueness: true, allow_blank: true

  validates_associated :user_roles

  validate :presence_of_email_or_cpf
  validate :validate_receive_news_fields, if: :has_to_validate_receive_news_fields?
  validate :can_not_be_a_cpf
  validate :can_not_be_an_email

  scope :ordered, -> { order(arel_table[:first_name].asc) }
  scope :email_ordered, -> { order(email: :asc)  }
  scope :authorized_email_and_sms, -> { where(arel_table[:authorize_email_and_sms].eq(true)) }
  scope :with_phone, -> { where(arel_table[:phone].not_eq(nil)).where(arel_table[:phone].not_eq("")) }
  scope :admin, -> { where(arel_table[:admin].eq(true)) }
  scope :by_unity_id, lambda { |unity_id| joins(:user_roles).where(user_roles: { unity_id: unity_id }) }
  scope :by_current_unity_id, lambda { |unity_id| where(current_unity_id: unity_id) }

  #search scopes
  scope :full_name, lambda { |full_name| where("unaccent(first_name || ' ' || last_name) ILIKE unaccent(?)", "%#{full_name}%")}
  scope :email, lambda { |email| where("unaccent(email) ILIKE unaccent(?)", "%#{email}%")}
  scope :login, lambda { |login| where("unaccent(login) ILIKE unaccent(?)", "%#{login}%")}
  scope :status, lambda { |status| where status: status }

  delegate :can_change_school_year?, to: :current_user_role, allow_nil: true

  def self.current=(user)
    Thread.current[:user] = user
  end

  def self.current
    Thread.current[:user]
  end

  def self.to_csv
    attributes = ["Nome", "Sobrenome", "E-mail", "Nome de usuário", "Celular"]

    CSV.generate(headers: true) do |csv|
      csv << attributes

      all.each do |user|
        csv << [user.first_name, user.last_name, user.email, user.login, user.phone]
      end
    end
  end

  def self.find_for_authentication(conditions)
    credential = conditions.fetch(:credentials)

    where(%Q(
      users.login = :credential OR
      users.email = :credential OR
      (
        users.cpf != '' AND
        REGEXP_REPLACE(users.cpf, '[^\\d]+', '', 'g') = REGEXP_REPLACE(:credential, '[^\\d]+', '', 'g')
      )
    ), credential: credential).first
  end

  def can_show?(feature)
    if feature == "general_configurations"
      return admin?
    end
    return true if admin?
    return unless current_user_role

    current_user_role.role.can_show?(feature)
  end

  def can_change?(feature)
    if feature == "general_configurations"
      return admin?
    end
    return true if admin?
    return unless current_user_role

    current_user_role.role.can_change?(feature)
  end

  def update_tracked_fields!(request)
    logins.create!(
      sign_in_ip: request.remote_ip
    )

    super
  end

  def active_for_authentication?
    super && actived?
  end

  def logged_as
    login.presence || email
  end

  def name
    "#{first_name} #{last_name}".strip
  end

  def activation_sent!
    update_column :activation_sent_at, DateTime.current
  end

  def activation_sent?
    self.activation_sent_at.present?
  end

  def raw_phone
    phone.gsub(/[^\d]/, '')
  end

  def student_api_codes
    codes = [students.pluck(:api_code)]
    codes.push(student.api_code) if student
    codes.flatten
  end

  def roles
    user_roles.includes(:role, :unity).map(&:role)
  end

  def set_current_user_role!(user_role_id)
    return false unless user_roles.exists?(id: user_role_id)

    update_column(:current_user_role_id, user_role_id)
  end

  def read_notifications!
    system_notification_targets.read!
  end

  def to_s
    return email unless name.strip.present?

    name
  end

  def navigation_display
    if first_name.present? && last_name.present?
      "#{first_name}.#{last_name.split(' ').last}"
    elsif first_name.present?
      "#{first_name}"
    elsif login.present?
      "#{login}"
    else
      ''
    end
  end

  def email=(value)
    write_attribute(:email, value) if value.present?
  end

  def cpf=(value)
    write_attribute(:cpf, value) if value.present?
  end

  def current_unity
    @current_unity ||= Unity.find_by_id(current_unity_id) || current_user_role.try(:unity)
  end

  def current_classroom
    return unless current_classroom_id
    @current_classroom ||= Classroom.find(current_classroom_id)
  end

  def current_discipline
    return unless current_discipline_id
    @current_discipline ||= Discipline.find(current_discipline_id)
  end

  def current_teacher
    if current_user_role.try(:role_teacher?)
      teacher
    elsif assumed_teacher_id
      Teacher.find_by_id(assumed_teacher_id)
    end
  end


  def can_receive_news_related_daily_teacher?
    roles.map(&:access_level).uniq.any?{|access_level| ["administrator", "employee", "teacher"].include? access_level}
  end

  def can_receive_news_related_tools_for_parents?
    roles.map(&:access_level).uniq.any?{|access_level| ["administrator", "employee", "parent", "student"].include? access_level}
  end

  def can_receive_news_related_all_matters?
    roles.map(&:access_level).uniq.any?{|access_level| ["administrator", "employee"].include? access_level}
  end

  def clear_allocation
    update_attribute(:current_user_role_id, nil)
    update_attribute(:current_classroom_id, nil)
    update_attribute(:current_discipline_id, nil)
    update_attribute(:current_unity_id, nil)
    update_attribute(:assumed_teacher_id, nil)
  end

  def has_to_validate_receive_news_fields?
    has_to_validate_receive_news_fields == true || has_to_validate_receive_news_fields == 'true'
  end

  def current_access_level
    return unless current_user_role
    current_user_role.role.access_level
  end

  protected

  def email_required?
    false
  end

  def presence_of_email_or_cpf
    return if errors[:email].any? || errors[:cpf].any?

    if email.blank? && cpf.blank?
      errors.add(:base, :must_inform_email_or_cpf)
    end
  end

  def ensure_has_no_audits
    user_id = self.id
    query = "SELECT COUNT(*) FROM audits WHERE audits.user_id = '#{user_id}'"
    audits_count = ActiveRecord::Base.connection.execute(query).first.fetch("count").to_i
    if audits_count > 0
      errors.add(:base, "")
      false
    end
  end

  def verify_receive_news_fields
    return true unless persisted?
    self.receive_news_related_daily_teacher = false unless can_receive_news_related_daily_teacher?
    self.receive_news_related_tools_for_parents = false unless can_receive_news_related_tools_for_parents?
    self.receive_news_related_all_matters = false unless can_receive_news_related_all_matters?

    if !receive_news?
      self.receive_news_related_daily_teacher = false
      self.receive_news_related_tools_for_parents = false
      self.receive_news_related_all_matters = false
    end
    true
  end

  def validate_receive_news_fields
    if receive_news? && !(
        receive_news_related_daily_teacher? ||
         receive_news_related_tools_for_parents? || receive_news_related_all_matters?)
      errors.add(:receive_news, :must_fill_receive_news_options)
    end
  end

  def can_not_be_a_cpf
    return unless CPF.valid?(login)

    errors.add(:login, :can_not_be_a_cpf)
  end

  def can_not_be_an_email
    return unless login =~ /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i

    errors.add(:login, :can_not_be_an_email)
  end
end
