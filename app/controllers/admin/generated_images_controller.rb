module Admin
  class GeneratedImagesController < BaseController
    MAX_UPLOAD_BYTES = 10.megabytes
    ALLOWED_UPLOAD_TYPES = %w[image/png image/jpeg image/webp].freeze
    IMAGEABLE_TYPES = {
      "Meeting" => Meeting,
      "Topic" => Topic
    }.freeze

    def create
      imageable = find_imageable
      file = upload_file

      unless valid_upload?(file)
        redirect_to return_path, alert: "Upload must be a PNG, JPEG, or WebP under 10 MB."
        return
      end

      image = imageable.generated_images.new(upload_params.except(:file).merge(
        status: "ready",
        purpose: upload_purpose,
        admin_override: true,
        uploaded_by: Current.user,
        generated_at: Time.current,
        source_generation_tier: "admin_upload",
        requested_size: upload_requested_size,
        output_format: upload_output_format
      ))

      GeneratedImage.transaction do
        image.save!
        image.file.attach(file)
        supersede_previous_ready_images(imageable, except: image)
      end

      redirect_to return_path, notice: "Uploaded image saved."
    rescue ActiveRecord::RecordNotFound
      redirect_to return_path, alert: "Imageable not found."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to return_path, alert: e.record.errors.full_messages.to_sentence
    rescue ActionController::ParameterMissing
      redirect_to return_path, alert: "Upload parameters are missing."
    end

    def regenerate
      imageable = find_imageable
      regenerate_options = { force: true }
      custom_prompt = params[:custom_prompt].presence
      regenerate_options[:custom_prompt] = custom_prompt if custom_prompt.present?

      case imageable
      when Meeting
        GeneratedImages::GenerateForMeetingJob.perform_later(imageable.id, **regenerate_options)
      when Topic
        GeneratedImages::GenerateForTopicJob.perform_later(imageable.id, **regenerate_options)
      end

      redirect_to return_path, notice: "Image regeneration queued."
    rescue ActiveRecord::RecordNotFound
      redirect_to return_path, alert: "Imageable not found."
    end

    def disable
      imageable = find_imageable
      image = imageable.generated_images.find(params.require(:image_id))
      image.update!(status: "disabled")

      redirect_to return_path, notice: "Image disabled."
    rescue ActiveRecord::RecordNotFound
      redirect_to return_path, alert: "Image not found."
    end

    private

    def find_imageable
      model = IMAGEABLE_TYPES[params[:imageable_type].to_s]
      raise ActiveRecord::RecordNotFound unless model

      model.find(params[:imageable_id])
    end

    def upload_params
      params.require(:generated_image).permit(:file, :purpose, :requested_size)
    end

    def upload_file
      upload_params[:file]
    end

    def valid_upload?(file)
      return false unless file.respond_to?(:size)
      return false if file.size.to_i > MAX_UPLOAD_BYTES

      detected_type = detected_upload_type(file)
      ALLOWED_UPLOAD_TYPES.include?(detected_type)
    end

    def detected_upload_type(file)
      tempfile = file.respond_to?(:tempfile) ? file.tempfile : file
      tempfile.rewind if tempfile.respond_to?(:rewind)
      Marcel::Magic.by_magic(tempfile)&.type.to_s
    ensure
      tempfile.rewind if tempfile.respond_to?(:rewind)
    end

    def upload_purpose
      upload_params[:purpose].presence || GeneratedImages::Generator::DEFAULT_PURPOSE
    end

    def upload_requested_size
      upload_params[:requested_size].presence || GeneratedImages::Generator::DEFAULT_SIZE
    end

    def upload_output_format
      detected_upload_type(upload_file).split("/").last.presence
    end

    def supersede_previous_ready_images(imageable, except:)
      imageable.generated_images.ready.where.not(id: except.id).find_each do |existing|
        existing.update!(status: "superseded")
      end
    end

    def return_path
      path = params[:return_to].to_s
      return admin_root_path unless path.start_with?("/")
      return admin_root_path if path.start_with?("//") || path.include?("\\")

      path
    end
  end
end
