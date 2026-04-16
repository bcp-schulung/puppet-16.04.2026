require 'spec_helper'

describe 'mynginx' do
  let(:facts) do
    {
      os: {
        'family' => 'Debian',
        'name'   => 'Ubuntu',
      },
    }
  end

  it { is_expected.to compile.with_all_deps }

  it { is_expected.to contain_package('nginx').with_ensure('installed') }
  it { is_expected.to contain_service('nginx').with_ensure('running').with_enable(true) }
  it { is_expected.to contain_file('/etc/nginx/nginx.conf') }
  it { is_expected.to contain_file('/usr/share/nginx/html/40x.html') }
  it { is_expected.to contain_file('/usr/share/nginx/html/50x.html') }
end
