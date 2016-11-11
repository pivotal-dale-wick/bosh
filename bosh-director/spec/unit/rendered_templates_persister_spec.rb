require 'spec_helper'

module Bosh::Director
  describe RenderedTemplatesPersister do

    let(:blobstore) { instance_double('Bosh::Blobstore::BaseClient') }
    let(:instance_plan) { instance_double('Bosh::Director::DeploymentPlan::InstancePlan') }
    let(:instance) { instance_double('Bosh::Director::DeploymentPlan::Instance') }
    let(:instance_model) { instance_double('Bosh::Director::Models::Instance')}

    let(:latest_rendered_templates_archive) { instance_double('Bosh::Director::Models::RenderedTemplatesArchive')}
    let(:rendered_templates_archive) { instance_double('Bosh::Director::Core::Templates::RenderedTemplatesArchive') }

    let(:rendered_job_instance) { instance_double('Bosh::Director::Core::Templates::RenderedJobInstance')}

    let(:compressed_rendered_job_templates) { instance_double('Bosh::Director::Core::Templates::CompressedRenderedJobTemplates') }

    let(:smurf_time) { Time.now }

    let(:old_blobstore_id) { 'smurfs-blob-id' }
    let(:old_sha1) { 'smurfs-blob-sha1' }

    let(:new_blobstore_id) { 'generated-blobstore-id' }
    let(:new_sha1) { 'generated-sha1' }

    let(:old_configuration_hash) { 'stored-configuration-hash' }
    let(:matching_configuration_hash) { 'stored-configuration-hash' }
    let(:non_matching_configuration_hash) { 'some-other-configuration-hash'}

    let(:compressed_template_contents) { 'some-text-be-be-saved'}

    describe 'self.persist' do
      def perform
        RenderedTemplatesPersister.persist(logger, blobstore, instance_plan)
      end

      before do
        allow(instance_plan).to receive(:instance).and_return(instance)
        allow(instance_plan).to receive(:rendered_templates).and_return(rendered_job_instance)

        allow(instance).to receive(:model).and_return(instance_model)
        allow(instance).to receive(:rendered_templates_archive=)

        allow(instance_model).to receive(:latest_rendered_templates_archive).and_return(latest_rendered_templates_archive)
        allow(instance_model).to receive(:add_rendered_templates_archive)

        allow(latest_rendered_templates_archive).to receive(:blobstore_id).and_return(old_blobstore_id)
        allow(latest_rendered_templates_archive).to receive(:sha1).and_return(old_sha1)
        allow(latest_rendered_templates_archive).to receive(:content_sha1).and_return(old_configuration_hash)
        allow(latest_rendered_templates_archive).to receive(:update)

        allow(rendered_job_instance).to receive(:generate_compressed_templates).and_return(compressed_rendered_job_templates)

        allow(blobstore).to receive(:create).with(compressed_template_contents).and_return(new_blobstore_id)

        allow(compressed_rendered_job_templates).to receive(:sha1).and_return(new_sha1)
        allow(compressed_rendered_job_templates).to receive(:contents).and_return(compressed_template_contents)

        allow(Time).to receive(:now).and_return(smurf_time)
      end

      context 'when rendered templates do not exist for an instance' do
        before do
          allow(instance_plan).to receive(:rendered_templates).and_return(nil)
        end

        it 'returns without persisting templates in blobstore' do
          expect(blobstore).to_not receive(:create)
          expect(instance_model).to_not receive(:add_rendered_templates_archive)
          expect(latest_rendered_templates_archive).to_not receive(:update)
          expect(Bosh::Director::Core::Templates::RenderedTemplatesArchive).to_not receive(:new)
          perform
        end
      end

      context 'when a rendered templates archive already exists in the DB' do

        context 'when the stored templates config hash matches the new templates config hash' do
          before do
            allow(instance).to receive(:configuration_hash).and_return(matching_configuration_hash)
          end

          context 'when blobstore does not already have the templates' do

            before do
              allow(blobstore).to receive(:exists?).with(old_blobstore_id).and_return(false)
            end

            it 'persists the templates to the blobstore' do
              expect(blobstore).to receive(:create).with(compressed_template_contents)

              perform
            end

            it 'updates the DB with the new blobstore ID and sha1' do
              expect(latest_rendered_templates_archive).to receive(:update).with({:blobstore_id => new_blobstore_id, :sha1 => new_sha1})

              perform
            end

            it 'sets the templates archive to the instance plan instance' do
              expect(Bosh::Director::Core::Templates::RenderedTemplatesArchive).to receive(:new).with(new_blobstore_id, new_sha1).and_return(rendered_templates_archive)
              expect(instance).to receive(:rendered_templates_archive=).with(rendered_templates_archive)

              perform
            end
          end

          context 'when blobstore already has the templates' do
            before do
              allow(blobstore).to receive(:exists?).with(old_blobstore_id).and_return(true)
            end

            it 'sets the templates archive on the instance plan instance' do
              expect(Bosh::Director::Core::Templates::RenderedTemplatesArchive).to receive(:new).with(old_blobstore_id, old_sha1).and_return(rendered_templates_archive)
              expect(instance).to receive(:rendered_templates_archive=).with(rendered_templates_archive)

              perform
            end

            it 'does NOT persist the templates to the blobstore' do
              expect(blobstore).to_not receive(:create)

              perform
            end
          end
        end

        context 'when stored templates config hash does not match the new templates config hash' do
          let(:new_templates_configuration_hash) { 'the new stuff' }

          before do
            allow(instance).to receive(:configuration_hash).and_return(non_matching_configuration_hash)
          end

          it 'persists the templates to the blobstore' do
            expect(blobstore).to receive(:create).with(compressed_template_contents)

            perform
          end

          it 'persists blob record in the database' do
            expect(instance_model).to receive(:add_rendered_templates_archive).with(
                :blobstore_id => new_blobstore_id,
                sha1: new_sha1,
                content_sha1: non_matching_configuration_hash,
                created_at: smurf_time,
              )

            perform
          end

          it 'sets the templates archive to the instance plan instance' do
            expect(Bosh::Director::Core::Templates::RenderedTemplatesArchive).to receive(:new).with(new_blobstore_id, new_sha1).and_return(rendered_templates_archive)
            expect(instance).to receive(:rendered_templates_archive=).with(rendered_templates_archive)

            perform
          end
        end
      end

      context 'when a rendered templates archive already does NOT exist in the DB' do
        before do
          allow(instance_model).to receive(:latest_rendered_templates_archive).and_return(nil)
          allow(instance).to receive(:configuration_hash).and_return(non_matching_configuration_hash)
        end

        it 'persists the templates to the blobstore' do
          expect(blobstore).to receive(:create).with(compressed_template_contents)

          perform
        end

        it 'persists blob record in the database' do
          expect(instance_model).to receive(:add_rendered_templates_archive).with(
              blobstore_id: new_blobstore_id,
              sha1: new_sha1,
              content_sha1: non_matching_configuration_hash,
              created_at: smurf_time,
          )

          perform
        end

        it 'sets the templates archive to the instance plan instance' do
          expect(Bosh::Director::Core::Templates::RenderedTemplatesArchive).to receive(:new).with(new_blobstore_id, new_sha1).and_return(rendered_templates_archive)
          expect(instance).to receive(:rendered_templates_archive=).with(rendered_templates_archive)

          perform
        end
      end
    end

  end
end