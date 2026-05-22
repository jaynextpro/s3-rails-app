class UploadsController < ApplicationController
  protect_from_forgery with: :null_session, only: [:create, :destroy]
  require 'aws-sdk-s3'

  MAX_FILE_SIZE = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  # Presigned object URLs are intentionally short-lived (60 seconds).
  PRESIGNED_URL_EXPIRY = 60

  def new
  end

  def create
    file = params[:image]

    if file.blank? || !file.respond_to?(:original_filename)
      return render json: { success: false, message: 'Por favor selecciona una imagen antes de subir.' },
                    status: :unprocessable_entity
    end

    unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
      return render json: { success: false, message: 'Formato no válido. Usa una imagen JPG, PNG, GIF o WEBP.' },
                    status: :unprocessable_entity
    end

    if file.size > MAX_FILE_SIZE
      return render json: { success: false, message: 'La imagen supera el tamaño máximo permitido de 10 MB.' },
                    status: :unprocessable_entity
    end

    s3 = Aws::S3::Resource.new(
      region: ENV['AWS_BUCKET_REGION'],
      credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY'], ENV['AWS_SECRET_KEY'])
    )
    key = "#{Time.now.to_i}-#{file.original_filename}"
    obj = s3.bucket(ENV['AWS_BUCKET_NAME']).object(key)
    obj.upload_file(file.tempfile, content_type: file.content_type)

    signer = Aws::S3::Presigner.new(client: s3.client)
    url = signer.presigned_url(:get_object,
                               bucket: ENV['AWS_BUCKET_NAME'],
                               key: key,
                               expires_in: 3600)

    render json: { success: true, message: 'La imagen se subió correctamente!', data: { url: url } }
  rescue Aws::Errors::MissingCredentialsError, Aws::Errors::MissingRegionError
    render json: { success: false, message: 'El servidor no tiene configuradas las credenciales de AWS.' },
           status: :service_unavailable
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("S3 upload failed: #{e.class} - #{e.message}")
    render json: { success: false, message: 'No se pudo subir la imagen a S3. Inténtalo de nuevo.' },
           status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error("Upload failed: #{e.class} - #{e.message}")
    render json: { success: false, message: 'Ocurrió un error inesperado al subir la imagen.' },
           status: :internal_server_error
  end

  # GET /uploads — list every object in the bucket, each with a short-lived preview URL.
  def index
    s3 = s3_resource
    signer = Aws::S3::Presigner.new(client: s3.client)

    objects = s3.bucket(ENV['AWS_BUCKET_NAME']).objects.map do |obj|
      {
        key: obj.key,
        size: obj.size,
        last_modified: obj.last_modified,
        url: signer.presigned_url(:get_object,
                                  bucket: ENV['AWS_BUCKET_NAME'],
                                  key: obj.key,
                                  expires_in: PRESIGNED_URL_EXPIRY)
      }
    end

    render json: { success: true, expires_in: PRESIGNED_URL_EXPIRY, data: { objects: objects } }
  end

  # DELETE /uploads?key=... — remove a single object from the bucket.
  def destroy
    s3_resource.bucket(ENV['AWS_BUCKET_NAME']).object(params[:key]).delete

    render json: { success: true, message: 'El objeto se elimino correctamente!' }
  end

  private

  def s3_resource
    Aws::S3::Resource.new(
      region: ENV['AWS_BUCKET_REGION'],
      credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY'], ENV['AWS_SECRET_KEY'])
    )
  end
end
