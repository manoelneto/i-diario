class GeneralConfigurationsController < ApplicationController
  after_action :clear_cache, only: :update

  def edit
    @general_configuration = GeneralConfiguration.current

    authorize @general_configuration
  end

  def update
    @general_configuration = GeneralConfiguration.current
    @general_configuration.attributes = permitted_attributes

    authorize @general_configuration

    if @general_configuration.save
      respond_with @general_configuration, location: edit_general_configurations_path
    else
      render :edit
    end
  end

  def history
    @general_configuration = GeneralConfiguration.current

    authorize @general_configuration

    respond_with @general_configuration
  end

  protected

  def permitted_attributes
    params.require(:general_configuration).permit(
      :security_level,
      :students_default_role_id,
      :employees_default_role_id,
      :parents_default_role_id,
      :allows_after_sales_relationship,
      :display_header_on_all_reports_pages,
      :max_descriptive_exam_character_count,
      :support_url,
      :copyright_name,
      :show_school_term_recovery_in_exam_record_report
    )
  end

  def clear_cache
    Rails.cache.delete("#{current_entity.id}_entity_copyright")
    Rails.cache.delete("#{current_entity.id}_entity_website")
  end
end
