module Bosh::Director
  class RenderedTemplatesPersister
    def self.persist(logger, blobstore, instance_plan)
      instance = instance_plan.instance

      rendered_templates_archive_model = instance.model.latest_rendered_templates_archive

      if rendered_templates_archive_model && rendered_templates_archive_model.content_sha1 == instance.configuration_hash
        if !blobstore.exists?(rendered_templates_archive_model.blobstore_id)
          compressed_templates = instance_plan.rendered_templates.generate_compressed_templates

          blobstore_id = blobstore.create(compressed_templates.contents)
          archive_sha1 = compressed_templates.sha1

          rendered_templates_archive_model.update({
            :blobstore_id => blobstore_id,
            :sha1 => archive_sha1
          })
        else
          blobstore_id = rendered_templates_archive_model.blobstore_id
          archive_sha1 = rendered_templates_archive_model.sha1
        end

      else
        compressed_templates = instance_plan.rendered_templates.generate_compressed_templates

        archive_sha1 = compressed_templates.sha1
        blobstore_id = blobstore.create(compressed_templates.contents)

        instance.model.add_rendered_templates_archive(
          blobstore_id: blobstore_id,
          sha1: compressed_templates.sha1,
          content_sha1: instance.configuration_hash,
          created_at: Time.now,
        )
      end

      rendered_templates_archive = Core::Templates::RenderedTemplatesArchive.new(
        blobstore_id,
        archive_sha1,
      )
      instance.rendered_templates_archive = rendered_templates_archive
    end
  end
end
