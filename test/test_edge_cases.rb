# frozen_string_literal: true

require_relative 'test_helper'

class TestServerEdgeCases < TSMTestCase
  def setup
    super
    write_machine_id('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')
  end

  def test_local_with_whitespace_only_machine_id
    server = Server.new(
      alias_name: 'test', host: 'host.com', user: nil, port: 22,
      is_main: false, machine_id: '   '
    )
    # Whitespace-only machine_id should NOT match (not local)
    refute server.local?
  end

  def test_local_with_empty_string_machine_id
    server = Server.new(
      alias_name: 'test', host: nil, user: nil, port: 22,
      is_main: false, machine_id: ''
    )
    # Falls through to legacy check: nil host → local
    assert server.local?
  end

  def test_ssh_target_with_empty_string_user
    server = Server.new(
      alias_name: 'prod', host: 'host.com', user: '', port: 22,
      is_main: false, machine_id: 'other-id'
    )
    assert_equal 'host.com', server.ssh_target
  end

  def test_to_line_round_trip
    original = Server.new(
      alias_name: 'prod', host: 'prod.example.com', user: 'deploy', port: 2222,
      is_main: true, machine_id: 'abc-123-def'
    )
    line = original.to_line
    parts = line.split('|')

    reconstructed = Server.new(
      alias_name: parts[0],
      host: parts[1]&.empty? ? nil : parts[1],
      user: parts[2]&.empty? ? nil : parts[2],
      port: (parts[3] || 22).to_i,
      is_main: parts[4] == 'true',
      machine_id: parts[5]&.empty? ? nil : parts[5]
    )

    assert_equal original.alias_name, reconstructed.alias_name
    assert_equal original.host, reconstructed.host
    assert_equal original.user, reconstructed.user
    assert_equal original.port, reconstructed.port
    assert_equal original.is_main, reconstructed.is_main
    assert_equal original.machine_id, reconstructed.machine_id
  end
end

class TestServerManagerEdgeCases < TSMTestCase
  def test_load_servers_with_only_pipes
    write_servers_file("|||||\n")
    servers = ServerManager.load_servers
    # Should parse but result in a mostly-empty server
    assert_equal 1, servers.length
  end

  def test_load_servers_with_non_numeric_port
    write_servers_file("test|host.com|user|abc|false|\n")
    servers = ServerManager.load_servers
    assert_equal 0, servers.first.port  # "abc".to_i == 0
  end

  def test_load_servers_with_extra_fields
    write_servers_file("test|host.com|user|22|true|id-123|extra|fields\n")
    servers = ServerManager.load_servers
    assert_equal 1, servers.length
    assert_equal 'test', servers.first.alias_name
  end

  def test_remove_duplicates_three_way
    servers = [
      Server.new(alias_name: 'prod', host: 'a.com', user: nil, port: 22, is_main: false, machine_id: nil),
      Server.new(alias_name: 'prod', host: 'b.com', user: nil, port: 22, is_main: false, machine_id: nil),
      Server.new(alias_name: 'prod', host: 'c.com', user: nil, port: 22, is_main: false, machine_id: 'real-id'),
    ]

    ServerManager.remove_duplicates!(servers)
    assert_equal 1, servers.length
    assert_equal 'real-id', servers.first.machine_id
  end

  def test_remove_duplicates_preserves_order_of_unique
    servers = [
      Server.new(alias_name: 'alpha', host: nil, user: nil, port: 22, is_main: false, machine_id: 'a'),
      Server.new(alias_name: 'beta', host: nil, user: nil, port: 22, is_main: false, machine_id: 'b'),
      Server.new(alias_name: 'gamma', host: nil, user: nil, port: 22, is_main: false, machine_id: 'c'),
    ]

    ServerManager.remove_duplicates!(servers)
    assert_equal %w[alpha beta gamma], servers.map(&:alias_name)
  end

  def test_save_creates_config_dir
    FileUtils.rm_rf(CONFIG_DIR)
    servers = [Server.new(alias_name: 'local', host: nil, user: nil, port: 22, is_main: false, machine_id: nil)]
    ServerManager.save_servers(servers)
    assert Dir.exist?(CONFIG_DIR)
    assert File.exist?(SERVERS_FILE)
  end
end

class TestRemoteExecutorEdgeCases < TSMTestCase
  def setup
    super
    write_machine_id('local-id')
  end

  def test_build_ssh_command_escapes_target
    server = Server.new(
      alias_name: 'test', host: 'host.example.com', user: 'deploy', port: 22,
      is_main: false, machine_id: 'remote-id'
    )
    cmd = RemoteExecutor.build_ssh_command(server, 'echo test')
    # Target should be properly escaped
    assert_includes cmd, 'deploy@host.example.com'
  end

  def test_format_age_boundary_values
    assert_equal 'now', RemoteExecutor.format_age(59)
    assert_equal '1m', RemoteExecutor.format_age(60)
    assert_equal '59m', RemoteExecutor.format_age(3599)
    assert_equal '1h', RemoteExecutor.format_age(3600)
    assert_equal '23h', RemoteExecutor.format_age(86399)
    assert_equal '1d', RemoteExecutor.format_age(86400)
  end

  def test_format_age_large_values
    assert_equal '365d', RemoteExecutor.format_age(365 * 86400)
  end
end

class TestMachineIdEdgeCases < TSMTestCase
  def test_generate_returns_different_ids
    id1 = MachineId.generate!
    id2 = MachineId.generate!
    refute_equal id1, id2
  end

  def test_load_with_extra_whitespace
    File.write(MACHINE_ID_FILE, "  abc-123  \n\n")
    assert_equal 'abc-123', MachineId.load
  end
end
