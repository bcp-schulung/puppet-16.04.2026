require 'spec_helper'

describe 'mynginx::site' do
  let(:title) { 'default' }
  let(:pre_condition) do
    <<~PUPPET
      class { 'mynginx':
        manage_default_site => false,
      }
    PUPPET
  end
  let(:params) do
    {
      docroot: '/srv/my-node-content',
      manage_index: true,
    }
  end
  let(:facts) do
    {
      os: {
        'family' => 'Debian',
        'name'   => 'Ubuntu',
      },
    }
  end

  it { is_expected.to compile.with_all_deps }

  it { is_expected.to contain_file('/srv/my-node-content').with_ensure('directory') }
  it { is_expected.to contain_file('/srv/my-node-content/index.html') }
  it { is_expected.to contain_file('/etc/nginx/sites-available/default') }
  it { is_expected.to contain_file('/etc/nginx/sites-enabled/default').with_ensure('link') }
end
