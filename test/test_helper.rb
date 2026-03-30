# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

# Shared constant override logic
TSM_TEST_CONSTANTS = %w[
  CONFIG_DIR CONFIG_FILE LAST_CHECK_FILE AVAILABLE_VERSION_FILE
  MACHINE_ID_FILE SERVERS_FILE INSTALL_PATH
].freeze

def self.build_test_paths(tmpdir)
  {
    'CONFIG_DIR'             => File.join(tmpdir, 'config'),
    'CONFIG_FILE'            => File.join(tmpdir, 'config', 'config'),
    'LAST_CHECK_FILE'        => File.join(tmpdir, 'config', 'last_check'),
    'AVAILABLE_VERSION_FILE' => File.join(tmpdir, 'config', 'available_version'),
    'MACHINE_ID_FILE'        => File.join(tmpdir, 'config', 'machine-id'),
    'SERVERS_FILE'           => File.join(tmpdir, 'config', 'servers'),
    'INSTALL_PATH'           => File.join(tmpdir, 'bin', 'tsm'),
  }
end

def self.override_tsm_constants!(tmpdir)
  build_test_paths(tmpdir).each do |name, value|
    Object.send(:remove_const, name) if Object.const_defined?(name)
    Object.const_set(name, value)
  end
end

TEST_TMP_BASE = Dir.mktmpdir('tsm-test')

# Load tsm with warnings suppressed to avoid constant redefinition noise
override_tsm_constants!(TEST_TMP_BASE)
original_verbose = $VERBOSE
$VERBOSE = nil
load File.expand_path('../../tsm', __FILE__)
$VERBOSE = original_verbose

# Re-override since loading tsm redefines the constants
override_tsm_constants!(TEST_TMP_BASE)

at_exit { FileUtils.rm_rf(TEST_TMP_BASE) }

# Base test class with temp directory support
class TSMTestCase < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('tsm-test-case')
    override_constants!(@tmpdir)
    Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
    MachineId.reset_cache!
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    MachineId.reset_cache!
  end

  private

  def config_dir
    File.join(@tmpdir, 'config')
  end

  def override_constants!(tmpdir)
    {
      'CONFIG_DIR'             => File.join(tmpdir, 'config'),
      'CONFIG_FILE'            => File.join(tmpdir, 'config', 'config'),
      'LAST_CHECK_FILE'        => File.join(tmpdir, 'config', 'last_check'),
      'AVAILABLE_VERSION_FILE' => File.join(tmpdir, 'config', 'available_version'),
      'MACHINE_ID_FILE'        => File.join(tmpdir, 'config', 'machine-id'),
      'SERVERS_FILE'           => File.join(tmpdir, 'config', 'servers'),
      'INSTALL_PATH'           => File.join(tmpdir, 'bin', 'tsm'),
    }.each do |name, value|
      Object.send(:remove_const, name) if Object.const_defined?(name)
      Object.const_set(name, value)
    end
  end

  def write_servers_file(content)
    File.write(SERVERS_FILE, content)
  end

  def write_machine_id(id)
    File.write(MACHINE_ID_FILE, id)
    MachineId.reset_cache!
  end
end
