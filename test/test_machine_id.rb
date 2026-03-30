# frozen_string_literal: true

require_relative 'test_helper'

class TestMachineId < TSMTestCase
  # --- generate! ---

  def test_generate_creates_valid_uuid
    id = MachineId.generate!
    refute_nil id
    assert_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, id)
  end

  def test_generate_writes_file
    MachineId.generate!
    assert File.exist?(MACHINE_ID_FILE)
    content = File.read(MACHINE_ID_FILE)
    assert_match(/^[0-9a-f-]{36}$/, content)
  end

  # --- load ---

  def test_load_returns_nil_when_file_missing
    assert_nil MachineId.load
  end

  def test_load_reads_existing_id
    File.write(MACHINE_ID_FILE, "test-uuid-1234\n")
    assert_equal 'test-uuid-1234', MachineId.load
  end

  def test_load_strips_whitespace
    File.write(MACHINE_ID_FILE, "  test-uuid  \n")
    assert_equal 'test-uuid', MachineId.load
  end

  # --- ensure! ---

  def test_ensure_creates_id_when_missing
    id = MachineId.ensure!
    refute_nil id
    assert File.exist?(MACHINE_ID_FILE)
  end

  def test_ensure_loads_existing_id
    File.write(MACHINE_ID_FILE, 'existing-id')
    id = MachineId.ensure!
    assert_equal 'existing-id', id
  end

  def test_ensure_creates_config_dir
    FileUtils.rm_rf(CONFIG_DIR)
    refute Dir.exist?(CONFIG_DIR)
    MachineId.ensure!
    assert Dir.exist?(CONFIG_DIR)
  end

  # --- current / reset_cache! ---

  def test_current_caches_value
    File.write(MACHINE_ID_FILE, 'cached-id')
    assert_equal 'cached-id', MachineId.current
    # Overwrite file - should still return cached value
    File.write(MACHINE_ID_FILE, 'new-id')
    assert_equal 'cached-id', MachineId.current
  end

  def test_reset_cache_clears_cached_value
    File.write(MACHINE_ID_FILE, 'old-id')
    MachineId.current  # cache it
    MachineId.reset_cache!
    File.write(MACHINE_ID_FILE, 'new-id')
    assert_equal 'new-id', MachineId.current
  end

  # --- exists? ---

  def test_exists_false_when_missing
    refute MachineId.exists?
  end

  def test_exists_true_when_present
    File.write(MACHINE_ID_FILE, 'some-id')
    assert MachineId.exists?
  end
end
