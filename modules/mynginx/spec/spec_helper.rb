require 'fileutils'

fixture_module_link = File.expand_path('fixtures/modules/mynginx', __dir__)
FileUtils.rm_rf(fixture_module_link) if File.symlink?(fixture_module_link)

require 'puppetlabs_spec_helper/module_spec_helper'
