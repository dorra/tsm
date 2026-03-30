# frozen_string_literal: true

require_relative 'test_helper'

class TestInstaller < TSMTestCase
  # --- detect_shell ---

  def test_detect_shell_returns_hash_with_name_and_rc
    result = Installer.detect_shell
    assert_kind_of Hash, result
    assert_includes ['bash', 'zsh'], result[:name]
    assert result[:rc].is_a?(String)
  end

  def test_detect_shell_with_zsh_env
    original = ENV['SHELL']
    ENV['SHELL'] = '/bin/zsh'
    result = Installer.detect_shell
    assert_equal 'zsh', result[:name]
    assert result[:rc].end_with?('.zshrc')
  ensure
    ENV['SHELL'] = original
  end

  def test_detect_shell_with_bash_env
    original = ENV['SHELL']
    ENV['SHELL'] = '/bin/bash'
    result = Installer.detect_shell
    assert_equal 'bash', result[:name]
  ensure
    ENV['SHELL'] = original
  end

  # --- path_configured? ---

  def test_path_configured_true_when_local_bin_in_rc
    shell_info = { name: 'bash', rc: File.join(@tmpdir, '.bashrc') }
    File.write(shell_info[:rc], 'export PATH="$HOME/.local/bin:$PATH"')
    assert Installer.path_configured?(shell_info)
  end

  def test_path_configured_false_when_not_in_rc
    shell_info = { name: 'bash', rc: File.join(@tmpdir, '.bashrc') }
    File.write(shell_info[:rc], '# empty shell config')
    refute Installer.path_configured?(shell_info)
  end

  def test_path_configured_false_when_rc_missing
    shell_info = { name: 'bash', rc: File.join(@tmpdir, 'nonexistent') }
    refute Installer.path_configured?(shell_info)
  end

  def test_path_configured_true_when_nil
    assert Installer.path_configured?(nil)
  end

  # --- installed? ---

  def test_installed_false_when_missing
    refute Installer.installed?
  end

  def test_installed_true_when_present_and_executable
    install_dir = File.dirname(INSTALL_PATH)
    FileUtils.mkdir_p(install_dir)
    File.write(INSTALL_PATH, '#!/usr/bin/env ruby')
    File.chmod(0755, INSTALL_PATH)
    assert Installer.installed?
  end
end
