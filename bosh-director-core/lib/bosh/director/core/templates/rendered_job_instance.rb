require 'bosh/director/core/templates'
require 'bosh/director/core/templates/rendered_templates_archive'
require 'bosh/director/core/templates/compressed_rendered_job_templates'
require 'digest/sha1'
require 'tempfile'
require 'base64'

module Bosh::Director::Core::Templates
  class RenderedJobInstance
    def initialize(job_templates)
      @job_templates = job_templates
    end

    def configuration_hash
      instance_digest = Digest::SHA1.new

      @job_templates.sort { |x, y| x.name <=> y.name }.each do |rendered_job_template|
        bound_templates = ''
        bound_templates << rendered_job_template.monit
        bound_templates << rendered_job_template.name

        rendered_job_template.templates.sort { |x, y| x.src_name <=> y.src_name }.each do |template_file|
          bound_templates << template_file.contents
          bound_templates << template_file.dest_name
        end

        instance_digest << bound_templates
      end

      instance_digest.hexdigest
    end

    def template_hashes
      @job_templates.reduce({}) do |h, rendered_job_template|
        h.merge(rendered_job_template.name => rendered_job_template.template_hash)
      end
    end

    def persist_on_blobstore(blobstore)
      file = Tempfile.new('compressed-rendered-job-templates')

      compressed_archive = CompressedRenderedJobTemplates.new(file.path)
      compressed_archive.write(@job_templates)

      blobstore_id = blobstore.create(compressed_archive.contents)
      RenderedTemplatesArchive.new(blobstore_id, compressed_archive.sha1)
    ensure
      file.close!
    end

    def persist_through_agent(agent_client)
      file = Tempfile.new('compressed-rendered-job-templates')

      compressed_archive = CompressedRenderedJobTemplates.new(file.path)
      compressed_archive.write(@job_templates)

      generated_blob_id = SecureRandom.uuid
      sha1 = compressed_archive.sha1
      base64_encoded_templates = Base64.encode64(compressed_archive.contents.read)

      agent_client.upload_blob(generated_blob_id, sha1, base64_encoded_templates)

      RenderedTemplatesArchive.new(generated_blob_id, sha1)
    ensure
      file.close!
    end
  end
end
