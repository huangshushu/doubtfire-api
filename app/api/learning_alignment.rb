require 'grape'

module Api
  class LearningAlignment < Grape::API
    helpers AuthHelpers
    helpers AuthorisationHelpers
    helpers MimeCheckHelpers
    
    before do
      authenticated?
    end

    desc "Get the task/outcome alignment details for a unit or a project"
    params do
      requires :unit_id             , type: Integer,  desc: 'The id of the unit'
      optional :project_id          , type: Integer,  desc: 'The id of the student project to get the alignment from'
    end
    get '/units/:unit_id/learning_alignments' do
      unit = Unit.find(params[:unit_id])

      if ! authorise?(current_user, unit, :get_unit)
        error!({"error" => "You are not authorised to access this unit."}, 403)
      end

      if params[:project_id].nil?
        return unit.task_outcome_alignments
      else
        proj = unit.projects.find(params[:project_id])
        if ! authorise?(current_user, proj, :get)
          error!({"error" => "You are not authorised to access this project."}, 403)
        end
        return proj.task_outcome_alignments
      end
    end

    desc "Download CSV of task alignments in this unit"
    params do
      requires :unit_id             , type: Integer,  desc: 'The id of the unit'
      optional :project_id          , type: Integer,  desc: 'The id of the student project to get the alignment from'
    end
    get '/units/:unit_id/learning_alignments/csv' do
      unit = Unit.find(params[:unit_id])

      if ! authorise?(current_user, unit, :get_unit)
        error!({"error" => "You are not authorised to access this unit."}, 403)
      end

      if params[:project_id].nil?
        if not authorise? current_user, unit, :downloadCSV
          error!({"error" => "Not authorised to download CSV of task alignment in #{unit.code}"}, 403)
        end
        
        content_type "application/octet-stream"
        header['Content-Disposition'] = "attachment; filename=#{unit.code}-Alignment.csv "
        env['api.format'] = :binary
        unit.export_task_alignment_to_csv
      else
        proj = unit.projects.find(params[:project_id])
        if ! authorise?(current_user, proj, :get)
          error!({"error" => "You are not authorised to access this project."}, 403)
        end

        content_type "application/octet-stream"
        header['Content-Disposition'] = "attachment; filename=#{unit.code}-#{proj.student.name}-Task-Alignment.csv "
        env['api.format'] = :binary

        proj.export_task_alignment_to_csv
      end
    end


    desc "Upload CSV of task to outcome alignments"
    params do
      requires :file, type: Rack::Multipart::UploadedFile, :desc => "CSV upload file."
      optional :project_id, type: Integer,  desc: 'The id of the student project to upload the alignment to'
    end
    post '/units/:unit_id/learning_alignments/csv' do
      ensure_csv!(params[:file][:tempfile])

      unit = Unit.find(params[:unit_id])
      
      if ! authorise?(current_user, unit, :get_unit)
        error!({"error" => "You are not authorised to access this unit."}, 403)
      end

      if params[:project_id].nil?
        if not authorise? current_user, unit, :uploadCSV
          error!({"error" => "Not authorised to upload CSV of task alignment to #{unit.code}"}, 403)
        end
        
        # Actually import...
        unit.import_task_alignment_from_csv(params[:file][:tempfile], nil)
      else
        proj = unit.projects.find(params[:project_id])
        if ! authorise?(current_user, proj, :make_submission)
          error!({"error" => "You are not authorised to access this project."}, 403)
        end

        unit.import_task_alignment_from_csv(params[:file][:tempfile], proj)
      end
    end



    desc "Add an outcome to a unit's task definition"
    params do
      requires :unit_id             , type: Integer,  desc: 'The id of the unit'
      requires :learning_outcome_id , type: Integer,  desc: 'The id of the learning outcome'
      requires :task_definition_id  , type: Integer,  desc: 'The id of the task definition'
      optional :task_id             , type: Integer,  desc: 'The id of the task'
      requires :description         , type: String,   desc: 'The ILO''s description'
      requires :rating              , type: Integer,  desc: 'The rating for this link, indicating the strength of this alignment'
    end
    post '/units/:unit_id/learning_alignments' do
      unit = Unit.find(params[:unit_id])

      if params[:task_id].nil? && ! authorise?(current_user, unit, :update)
        error!({"error" => "You are not authorised to create task alignments in this unit."}, 403)
      end

      unit.learning_outcomes.find(params[:learning_outcome_id])

      task_def = unit.task_definitions.find(params[:task_definition_id])

      link_parameters = ActionController::Parameters.new(params)
                                          .permit(
                                            :task_definition_id,
                                            :learning_outcome_id,
                                            :task_id,
                                            :description,
                                            :rating
                                          )

      if ! params[:task_id].nil?
        task = unit.tasks.find(params[:task_id])

        if ! authorise?(current_user, task, :make_submission)
          error!({"error" => "You are not authorised to create outcome alignments for this task."}, 403)
        end

        link_parameters[:task_id] = task.id
      end

      LearningOutcomeTaskLink.create! link_parameters
    end

    desc "Update the alignment between a task and unit outcome"
    params do
      requires :id                  , type: Integer,  desc: 'The id of the task alignment'
      requires :unit_id             , type: Integer,  desc: 'The id of the unit'
      optional :description         , type: String,   desc: 'The description of the alignment'
      optional :rating              , type: Integer,  desc: 'The rating for this link, indicating the strength of this alignment'
    end
    put '/units/:unit_id/learning_alignments/:id' do
      unit = Unit.find(params[:unit_id])

      if params[:task_id].nil? && ! authorise?(current_user, unit, :update)
        error!({"error" => "You are not authorised to update the task alignments in this unit."}, 403)
      end

      align = unit.learning_outcome_task_links.find(params[:id])

      link_parameters = ActionController::Parameters.new(params)
                                          .permit(
                                            :description,
                                            :rating
                                          )

      if ! align.task_id.nil?
        task = align.task

        if ! authorise?(current_user, task, :make_submission)
          error!({"error" => "You are not authorised to update outcome alignments for this task."}, 403)
        end
      end

      align.update(link_parameters)
      align.save!
    end

    desc "Delete the alignment between a task and unit outcome"
    params do
      requires :id                  , type: Integer,  desc: 'The id of the task alignment'
      requires :unit_id             , type: Integer,  desc: 'The id of the unit'
    end
    delete '/units/:unit_id/learning_alignments/:id' do
      unit = Unit.find(params[:unit_id])

      if params[:task_id].nil? && ! authorise?(current_user, unit, :update)
        error!({"error" => "You are not authorised to update the task alignments in this unit."}, 403)
      end

      align = unit.learning_outcome_task_links.find(params[:id])

      if ! align.task_id.nil?
        task = align.task

        if ! authorise?(current_user, task, :make_submission)
          error!({"error" => "You are not authorised to update outcome alignments for this task."}, 403)
        end
      end

      align.destroy!
      nil
    end

  #   desc "Update the alignment between tasks and outcomes"
  #   params do
  #     requires :unit_id       , type: Integer,  desc: 'The unit ID for which the ILO belongs to'
  #     optional :name          , type: String,   desc: 'The ILO''s new name'
  #     optional :description   , type: String,   desc: 'The ILO''s new description'
  #     optional :ilo_number    , type: Integer,  desc: 'The ILO''s new sequence number'
  #   end
  #   put '/units/:unit_id/outcomes/:id' do
  #     unit = Unit.find(params[:unit_id])
  #     error!({"error" => "Unable to locate requested unit."}, 405) if unit.nil?

  #     if not (authorise? current_user, unit, :update)
  #       error!({"error" => "You are not authorised to update outcomes in this unit."}, 403)
  #     end

  #     ilo = unit.learning_outcomes.find(params[:id])
  #     error!({"error" => "Unable to locate outcome requested."}, 405) if ilo.nil?
      
  #     ilo_parameters = ActionController::Parameters.new(params)
  #                                         .permit(
  #                                           :name,
  #                                           :description
  #                                         )
  #     if params[:ilo_number]
  #       unit.move_ilo(ilo, params[:ilo_number])
  #     end                                  
  #     ilo.update!(ilo_parameters)
  #     ilo
  #   end

  #   desc "Delete ILO"
  #   params do
  #     requires :ilo_id           , type: Integer,  desc: 'The ILO ID for the ILO you wish to delete'
  #   end
  #   delete '/units/:unit_id/outcomes/:id' do
  #     unit = Unit.find(params[:unit_id])
  #     error!({"error" => "Unable to locate requested unit."}, 405) if unit.nil?

  #     if not (authorise? current_user, unit, :update)
  #       error!({"error" => "You are not authorised to delete outcomes in this unit."}, 403)
  #     end

  #     ilo = unit.learning_outcomes.find(params[:id])
  #     error!({"error" => "Unable to locate outcome requested."}, 405) if ilo.nil?

  #     ilo.destroy
  #     nil
  #   end
  end
end