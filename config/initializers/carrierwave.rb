# Document storage.
#
# DEFAULT: local disk (:file). Uploaded documents live on the host's encrypted
# EBS volume via the `uploads` Docker volume (see docker-compose.yml). This is the
# pilot choice — no third-party processor, smaller breach blast radius (SECURITY.md).
#
# This previously auto-switched to S3 (:fog) in staging/production/demo. On the box
# (RAILS_ENV=production) that silently routed uploads to S3 with placeholder creds,
# so document upload was broken. We now stay on :file unless an operator explicitly
# opts into S3 for a permanent solution by setting STORAGE_BACKEND=s3 (plus the
# AWS_*/FOG_* vars). Local-disk changes are still audited via paper_trail.
CarrierWave.configure do |config|
  if ENV['STORAGE_BACKEND'].to_s.downcase == 's3'
    config.fog_credentials = {
      provider: 'AWS',
      aws_access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      aws_secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      region: ENV['FOG_REGION']
    }
    config.storage = :fog
    config.fog_directory = ENV['FOG_DIRECTORY']
  else
    config.storage = :file
  end
end
