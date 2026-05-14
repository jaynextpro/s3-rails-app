class UploadsController < ApplicationController
  protect_from_forgery with: :null_session, only: [:create]
  require 'aws-sdk-s3'

  def new
  end

  def create
    file = params[:image]
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

    render json: { success: true, message: 'La imagen se subio correctamente!', data: { url: url } }
  end
end
