# frozen_string_literal: true

require_relative 'test_helper'

class TestRemoteExecutor < TSMTestCase
  def setup
    super
    write_machine_id('local-machine-id')
  end

  # --- build_ssh_command ---

  def test_build_ssh_command_standard_port
    server = Server.new(
      alias_name: 'prod', host: 'prod.example.com', user: 'deploy', port: 22,
      is_main: false, machine_id: 'remote-id'
    )
    cmd = RemoteExecutor.build_ssh_command(server, 'echo hello')

    assert_includes cmd, 'ssh'
    assert_includes cmd, 'deploy@prod.example.com'
    assert_includes cmd, 'echo hello'
    assert_includes cmd, '-o ConnectTimeout=5'
    assert_includes cmd, '-o BatchMode=yes'
    assert_includes cmd, '-o StrictHostKeyChecking=accept-new'
    refute_includes cmd, '-p '  # no port flag for 22
  end

  def test_build_ssh_command_custom_port
    server = Server.new(
      alias_name: 'staging', host: 'staging.example.com', user: 'deploy', port: 2222,
      is_main: false, machine_id: 'remote-id'
    )
    cmd = RemoteExecutor.build_ssh_command(server, 'tmux ls')

    assert_match(/-p '?2222'?/, cmd)
  end

  def test_build_ssh_command_includes_path_prefix
    server = Server.new(
      alias_name: 'prod', host: 'prod.com', user: 'deploy', port: 22,
      is_main: false, machine_id: 'remote-id'
    )
    cmd = RemoteExecutor.build_ssh_command(server, 'tmux ls')

    assert_includes cmd, '/opt/homebrew/bin'
    assert_includes cmd, '/usr/local/bin'
    assert_includes cmd, '$HOME/.local/bin'
  end

  def test_build_ssh_command_without_user
    server = Server.new(
      alias_name: 'prod', host: 'prod.example.com', user: nil, port: 22,
      is_main: false, machine_id: 'remote-id'
    )
    cmd = RemoteExecutor.build_ssh_command(server, 'echo test')

    assert_includes cmd, 'prod.example.com'
    refute_includes cmd, '@'  # no user@ prefix
  end

  # --- format_age ---

  def test_format_age_now
    assert_equal 'now', RemoteExecutor.format_age(0)
    assert_equal 'now', RemoteExecutor.format_age(30)
    assert_equal 'now', RemoteExecutor.format_age(59)
  end

  def test_format_age_minutes
    assert_equal '1m', RemoteExecutor.format_age(60)
    assert_equal '5m', RemoteExecutor.format_age(300)
    assert_equal '59m', RemoteExecutor.format_age(3599)
  end

  def test_format_age_hours
    assert_equal '1h', RemoteExecutor.format_age(3600)
    assert_equal '23h', RemoteExecutor.format_age(86399)
  end

  def test_format_age_days
    assert_equal '1d', RemoteExecutor.format_age(86400)
    assert_equal '7d', RemoteExecutor.format_age(604800)
  end
end
