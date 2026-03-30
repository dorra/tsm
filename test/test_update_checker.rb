# frozen_string_literal: true

require_relative 'test_helper'

class TestUpdateChecker < TSMTestCase
  # --- should_check? ---

  def test_should_check_false_when_not_installed
    # INSTALL_PATH doesn't exist
    refute UpdateChecker.should_check?
  end

  def test_should_check_true_when_installed_no_last_check
    install_dir = File.dirname(INSTALL_PATH)
    FileUtils.mkdir_p(install_dir)
    File.write(INSTALL_PATH, '#!/usr/bin/env ruby')
    File.chmod(0755, INSTALL_PATH)

    assert UpdateChecker.should_check?
  end

  def test_should_check_false_when_recently_checked
    install_dir = File.dirname(INSTALL_PATH)
    FileUtils.mkdir_p(install_dir)
    File.write(INSTALL_PATH, '#!/usr/bin/env ruby')
    File.chmod(0755, INSTALL_PATH)

    File.write(LAST_CHECK_FILE, Time.now.to_i.to_s)
    refute UpdateChecker.should_check?
  end

  def test_should_check_true_when_last_check_expired
    install_dir = File.dirname(INSTALL_PATH)
    FileUtils.mkdir_p(install_dir)
    File.write(INSTALL_PATH, '#!/usr/bin/env ruby')
    File.chmod(0755, INSTALL_PATH)

    File.write(LAST_CHECK_FILE, (Time.now.to_i - 86401).to_s)
    assert UpdateChecker.should_check?
  end

  # --- available_version ---

  def test_available_version_nil_when_no_file
    assert_nil UpdateChecker.available_version
  end

  def test_available_version_returns_cached_version
    File.write(AVAILABLE_VERSION_FILE, "2.0.0\n")
    assert_equal '2.0.0', UpdateChecker.available_version
  end

  def test_available_version_nil_when_empty_file
    File.write(AVAILABLE_VERSION_FILE, "")
    assert_nil UpdateChecker.available_version
  end

  # --- load_update_url ---

  def test_load_update_url_default
    assert_equal UPDATE_URL_DEFAULT, UpdateChecker.load_update_url
  end

  def test_load_update_url_custom
    File.write(CONFIG_FILE, "update_url=https://example.com/tsm\n")
    assert_equal 'https://example.com/tsm', UpdateChecker.load_update_url
  end
end
