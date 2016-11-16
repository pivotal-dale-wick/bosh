require 'rspec'
require 'yaml'
require 'bosh/template/evaluation_context'
require 'json'

describe 'director.yml.erb.erb' do
  let(:deployment_manifest_fragment) do
    {
      'properties' => {
        'ntp' => [
          '0.north-america.pool.ntp.org',
          '1.north-america.pool.ntp.org',
        ],
        'compiled_package_cache' => {},
        'blobstore' => {
          'address' => '10.10.0.7',
          'port' => 25251,
          'agent' => { 'user' => 'agent', 'password' => '75d1605f59b60' },
          'director' => {
            'user' => 'user',
            'password' => 'password'
          },
          'provider' => 'dav',
        },
        'nats' => {
          'user' => 'nats',
          'password' => '1a0312a24c0a0',
          'address' => '10.10.0.7',
          'port' => 4222
        },
        'director' => {
          'name' => 'vpc-bosh-idora',
          'backend_port' => 25556,
          'encryption' => false,
          'max_tasks' => 100,
          'max_threads' => 32,
          'enable_snapshots' => true,
          'enable_post_deploy' => false,
          'enable_nats_delivered_templates' => false,
          'generate_vm_passwords' => false,
          'remove_dev_tools' => false,
          'log_access_events_to_syslog' => false,
          'flush_arp' => false,
          'local_dns' => {
            'enabled' => false,
            'include_index' => false,
          },
          'ignore_missing_gateway' => false,
          'disks' => {
            'max_orphaned_age_in_days' => 3,
            'cleanup_schedule' => '0 0,30 * * * * UTC',
          },
          'events' => {
            'record_events' => false,
            'max_events' => 10000,
            'cleanup_schedule' => '0 * * * * * UTC'
          },
          'db' => {
            'adapter' => 'mysql2',
            'user' => 'ub45391e00',
            'password' => 'p4cd567d84d0e012e9258d2da30',
            'host' => 'bosh.hamazonhws.com',
            'port' => 3306,
            'database' => 'bosh',
            'connection_options' => {},
          },
          'config_server' => {
            'enabled' => false
          },
          'auto_fix_stateful_nodes' => true,
          'max_vm_create_tries' => 5,
          'user_management' => { 'provider' => 'local' },
          'trusted_certs' => "test_trusted_certs\nvalue",
        }
      }
    }
  end

  let(:erb_yaml) { File.read(File.join(File.dirname(__FILE__), '../jobs/director/templates/director.yml.erb.erb')) }

  subject(:parsed_yaml) do
    binding = Bosh::Template::EvaluationContext.new(deployment_manifest_fragment).get_binding
    YAML.load(ERB.new(erb_yaml).result(binding))
  end


  context 'given a generally valid manifest' do
    before do
      deployment_manifest_fragment['properties']['director']['cpi_job'] = 'vsphere'
    end

    context 'when using web dav blobstore' do
      before do
        expect(deployment_manifest_fragment['properties']['blobstore']['provider']).to eq('dav')
      end

      it 'should configure the paths' do
          expect(parsed_yaml['blobstore']['provider']).to eq('davcli')
          expect(parsed_yaml['blobstore']['options']['davcli_config_path']).to eq('/var/vcap/data/tmp/director')
          expect(parsed_yaml['blobstore']['options']['davcli_path']).to eq('/var/vcap/packages/davcli/bin/davcli')
      end
    end

    it 'should contain the trusted_certs field' do
      expect(parsed_yaml['trusted_certs']).to eq("test_trusted_certs\nvalue")
    end

    it 'should keep dynamic, COMPONENT-based logging paths' do
      expect(parsed_yaml['logging']['file']).to eq("/var/vcap/sys/log/director/<%= ENV['COMPONENT'] %>.debug.log")
    end

    context 'when domain name specified without all other dns properties' do
      before do
        deployment_manifest_fragment['properties']['dns'] = {
          'domain_name' => 'domain.name'
        }
      end

      it 'does not set the domain_name field appropriately' do
        expect(parsed_yaml['dns']).to be_nil
      end
    end

    context 'and when configured with a compiled_package_cache blobstore_path' do
      before do
        deployment_manifest_fragment['properties']['compiled_package_cache']['options'] = {
          'blobstore_path' => '/some/path'
        }
      end

      it 'sets the compiled_package_cache fields appropriately' do
        expect(parsed_yaml['compiled_package_cache']).to eq({
          'provider' => 'local',
          'options' => {
            'blobstore_path' => '/some/path'
          }
        })
      end
    end

    it 'dumps the director.backup_destination at the top level' do
      deployment_manifest_fragment['properties']['director'].merge!('backup_destination' => {
        'some_backup_url' => 'http://foo.bar.com',
        'how_much_to_back_up' => {
          'all_the_things' => true
        }
      })

      expect(parsed_yaml['backup_destination']).to eq({
        'some_backup_url' => 'http://foo.bar.com',
        'how_much_to_back_up' => {
          'all_the_things' => true
        }
      })
    end

    context 'events configuration' do
      context 'when enabled' do
        before do
          deployment_manifest_fragment['properties']['director']['events']['record_events'] = true
        end

        it 'renders correctly' do
          expect(parsed_yaml['record_events']).to eq(true)
        end

        it 'is a scheduled task' do
          expect(parsed_yaml['scheduled_jobs'].map{ |v| v['command'] }).to include('ScheduledEventsCleanup')
        end
      end

      context 'when disabled' do
        it 'renders correctly' do
          expect(parsed_yaml['record_events']).to eq(false)
        end

        it 'is a scheduled task' do
          expect(parsed_yaml['scheduled_jobs'].map{ |v| v['command'] }).to_not include('ScheduledEventsCleanup')
        end
      end
    end

    describe 'config server' do
      context 'when turned on' do
        before do
          deployment_manifest_fragment['properties']['director']['config_server'] = {
              'enabled' => true,
              'url' => 'https://config-server-host',
              'uaa' => {
                  'url' => 'fake-uaa-url',
                  'client_id' => 'fake-client-id',
                  'client_secret' => 'fake-client-secret',
                  'ca_cert' => 'fake-ca-cert'
              },
          }
        end

        it 'parses correctly' do
          expect(parsed_yaml['config_server']['enabled']).to eq(true)

          expect(parsed_yaml['config_server']['url']).to eq('https://config-server-host')
          expect(parsed_yaml['config_server']['ca_cert_path']).to eq('/var/vcap/jobs/director/config/config_server_ca.cert')

          expect(parsed_yaml['config_server']['uaa']['url']).to eq('fake-uaa-url')
          expect(parsed_yaml['config_server']['uaa']['client_id']).to eq('fake-client-id')
          expect(parsed_yaml['config_server']['uaa']['client_secret']).to eq('fake-client-secret')
          expect(parsed_yaml['config_server']['uaa']['ca_cert_path']).to eq('/var/vcap/jobs/director/config/uaa_server_ca.cert')
        end

        describe 'UAA properties' do
          it 'throws an error when uaa properties are not defined' do
            deployment_manifest_fragment['properties']['director']['config_server'] = {
                'enabled' => true,
                'url' => 'https://config-server-host',
            }
            expect { parsed_yaml['config_server'] }.to raise_error
          end

          it 'throws an error when uaa url is not defined' do
            deployment_manifest_fragment['properties']['director']['config_server'] = {
                'enabled' => true,
                'url' => 'https://config-server-host',
                'uaa' => {}
            }

            expect { parsed_yaml['config_server'] }.to raise_error(Bosh::Template::UnknownProperty, "Can't find property '[\"director.config_server.uaa.url\"]'")
          end

          it 'throws an error when uaa client id is not defined' do
            deployment_manifest_fragment['properties']['director']['config_server'] = {
                'enabled' => true,
                'url' => 'https://config-server-host',
                'uaa' => {
                    'url' => 'http://something.com',
                    'client_secret' => 'secret',
                    'ca_cert_path' => '/var/vcap/blah/to/go'
                }
            }

            expect { parsed_yaml['config_server'] }.to raise_error(Bosh::Template::UnknownProperty, "Can't find property '[\"director.config_server.uaa.client_id\"]'")
          end

          it 'throws an error when uaa client secret is not defined' do
            deployment_manifest_fragment['properties']['director']['config_server'] = {
                'enabled' => true,
                'url' => 'https://config-server-host',
                'uaa' => {
                    'url' => 'https://something.com',
                    'client_id' => 'id',
                    'ca_cert_path' => '/var/vcap/blah/to/go'
                }
            }

            expect { parsed_yaml['config_server'] }.to raise_error(Bosh::Template::UnknownProperty, "Can't find property '[\"director.config_server.uaa.client_secret\"]'")
          end

          it 'does not throw any error when all the uaa properties are defined' do
            deployment_manifest_fragment['properties']['director']['config_server'] = {
                'enabled' => true,
                'url' => 'https://config-server-host',
                'uaa' => {
                    'url' => 'https://something.com',
                    'client_id' => 'id',
                    'client_secret' => 'secret',
                    'ca_cert_path' => '/var/some/path'
                }
            }

            expect { parsed_yaml['config_server'] }.to_not raise_error
          end
        end
      end

      context 'when turned off' do
        before do
          deployment_manifest_fragment['properties']['director']['config_server']['enabled'] = false
        end

        it 'parses correctly' do
          expect(parsed_yaml['config_server']).to eq({"enabled"=>false})
        end
      end
    end

    describe 'enable_nats_delivered_templates' do
      context 'when set to true' do
        before do
          deployment_manifest_fragment['properties']['director']['enable_nats_delivered_templates'] = true
        end

        it 'parses correctly' do
          expect(parsed_yaml['enable_nats_delivered_templates']).to be_truthy
        end
      end

      context 'when set to false' do
        before do
          deployment_manifest_fragment['properties']['director']['enable_nats_delivered_templates'] = false
        end

        it 'parses correctly' do
          expect(parsed_yaml['enable_nats_delivered_templates']).to be_falsey
        end
      end
    end
  end

  describe 'ignore_missing_gateway property' do
    before do
      deployment_manifest_fragment['properties']['director']['cpi_job'] = 'test-cpi'
    end

    context 'when false' do
      it 'renders false' do
        expect(parsed_yaml['ignore_missing_gateway']).to be(false)
      end
    end

    context 'when true' do
      before do
        deployment_manifest_fragment['properties']['director']['ignore_missing_gateway'] = true
      end

      it 'renders true' do
        expect(parsed_yaml['ignore_missing_gateway']).to be(true)
      end
    end
  end

  context 'when configured to use a cpi_job' do
    before do
      deployment_manifest_fragment['properties']['director']['cpi_job'] = 'test-cpi'
    end

    it 'configures the cpi correctly' do
      expect(parsed_yaml['cloud']['provider']['name']).to eq('test-cpi')
      expect(parsed_yaml['cloud']['provider']['path']).to eq('/var/vcap/jobs/test-cpi/bin/cpi')
    end
  end

  context 'when ntp is provided' do
    before do
      deployment_manifest_fragment['properties']['director']['cpi_job'] = 'test-cpi'
      deployment_manifest_fragment['properties']['ntp'] = ['1.1.1.1', '2.2.2.2']
    end

    it 'configures the cpi correctly' do
      expect(parsed_yaml['cloud']['properties']['agent']['ntp']).to eq(['1.1.1.1', '2.2.2.2'])
    end
  end
end
