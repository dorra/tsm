# frozen_string_literal: true

require_relative 'test_helper'

class TestServerManager < TSMTestCase
  # --- load_servers ---

  def test_load_servers_returns_default_when_file_missing
    servers = ServerManager.load_servers
    assert_equal 1, servers.length
    assert_equal 'local', servers.first.alias_name
    assert_nil servers.first.host
  end

  def test_load_servers_parses_valid_config
    write_servers_file(<<~CONFIG)
      # TSM Server Configuration
      # Format: alias|host|user|port|is_main|machine_id

      local|||22|false|abc-123
      prod|prod.example.com|deploy|22|true|def-456
      staging|staging.example.com|deploy|2222|false|ghi-789
    CONFIG

    servers = ServerManager.load_servers
    assert_equal 3, servers.length

    local = servers[0]
    assert_equal 'local', local.alias_name
    assert_nil local.host
    assert_nil local.user
    assert_equal 22, local.port
    refute local.is_main
    assert_equal 'abc-123', local.machine_id

    prod = servers[1]
    assert_equal 'prod', prod.alias_name
    assert_equal 'prod.example.com', prod.host
    assert_equal 'deploy', prod.user
    assert_equal 22, prod.port
    assert prod.is_main
    assert_equal 'def-456', prod.machine_id

    staging = servers[2]
    assert_equal 'staging', staging.alias_name
    assert_equal 2222, staging.port
  end

  def test_load_servers_ignores_comments_and_blank_lines
    write_servers_file(<<~CONFIG)
      # This is a comment

      # Another comment
      local|||22|false|abc
    CONFIG

    servers = ServerManager.load_servers
    assert_equal 1, servers.length
    assert_equal 'local', servers.first.alias_name
  end

  def test_load_servers_returns_default_for_empty_file
    write_servers_file("")
    servers = ServerManager.load_servers
    assert_equal 1, servers.length
    assert_equal 'local', servers.first.alias_name
  end

  def test_load_servers_handles_missing_optional_fields
    write_servers_file("minimal|host.com\n")
    servers = ServerManager.load_servers
    assert_equal 1, servers.length
    assert_equal 'minimal', servers.first.alias_name
    assert_equal 'host.com', servers.first.host
  end

  # --- save_servers ---

  def test_save_and_load_round_trip
    original = [
      Server.new(alias_name: 'local', host: nil, user: nil, port: 22, is_main: false, machine_id: 'aaa'),
      Server.new(alias_name: 'prod', host: 'prod.com', user: 'deploy', port: 2222, is_main: true, machine_id: 'bbb'),
    ]

    ServerManager.save_servers(original)
    loaded = ServerManager.load_servers

    assert_equal original.length, loaded.length

    original.each_with_index do |orig, i|
      assert_equal orig.alias_name, loaded[i].alias_name
      if orig.host.nil?
          assert_nil loaded[i].host
        else
          assert_equal orig.host, loaded[i].host
        end
        if orig.user.nil?
          assert_nil loaded[i].user
        else
          assert_equal orig.user, loaded[i].user
        end
      assert_equal orig.port, loaded[i].port
      assert_equal orig.is_main, loaded[i].is_main
      assert_equal orig.machine_id, loaded[i].machine_id
    end
  end

  # --- remove_duplicates! ---

  def test_remove_duplicates_keeps_entry_with_machine_id
    servers = [
      Server.new(alias_name: 'prod', host: 'prod.com', user: nil, port: 22, is_main: false, machine_id: nil),
      Server.new(alias_name: 'prod', host: 'prod.com', user: nil, port: 22, is_main: false, machine_id: 'abc-123'),
    ]

    ServerManager.remove_duplicates!(servers)
    assert_equal 1, servers.length
    assert_equal 'abc-123', servers.first.machine_id
  end

  def test_remove_duplicates_no_duplicates
    servers = [
      Server.new(alias_name: 'local', host: nil, user: nil, port: 22, is_main: false, machine_id: 'aaa'),
      Server.new(alias_name: 'prod', host: 'prod.com', user: nil, port: 22, is_main: false, machine_id: 'bbb'),
    ]

    ServerManager.remove_duplicates!(servers)
    assert_equal 2, servers.length
  end

  # --- cleanup_legacy_local! ---

  def test_cleanup_legacy_local_removes_nil_host_when_machine_id_exists
    write_machine_id('my-machine-id')

    servers = [
      Server.new(alias_name: 'old-local', host: nil, user: nil, port: 22, is_main: false, machine_id: nil),
      Server.new(alias_name: 'new-local', host: nil, user: nil, port: 22, is_main: false, machine_id: 'my-machine-id'),
    ]

    ServerManager.cleanup_legacy_local!(servers)
    assert_equal 1, servers.length
    assert_equal 'my-machine-id', servers.first.machine_id
  end

  def test_cleanup_legacy_local_keeps_entries_when_no_self_entry
    # Write a machine_id that doesn't match any server
    write_machine_id('unique-machine-id')

    servers = [
      Server.new(alias_name: 'local', host: nil, user: nil, port: 22, is_main: false, machine_id: nil),
    ]

    ServerManager.cleanup_legacy_local!(servers)
    assert_equal 1, servers.length
  end

  # --- main_server ---

  def test_main_server_found
    servers = [
      Server.new(alias_name: 'local', host: nil, user: nil, port: 22, is_main: false, machine_id: nil),
      Server.new(alias_name: 'prod', host: 'prod.com', user: nil, port: 22, is_main: true, machine_id: nil),
    ]
    assert_equal 'prod', ServerManager.main_server(servers).alias_name
  end

  def test_main_server_not_found
    servers = [
      Server.new(alias_name: 'local', host: nil, user: nil, port: 22, is_main: false, machine_id: nil),
    ]
    assert_nil ServerManager.main_server(servers)
  end

  # --- set_main ---

  def test_set_main_marks_correct_server
    servers = [
      Server.new(alias_name: 'local', host: nil, user: nil, port: 22, is_main: true, machine_id: nil),
      Server.new(alias_name: 'prod', host: 'prod.com', user: nil, port: 22, is_main: false, machine_id: nil),
    ]

    ServerManager.set_main(servers, 'prod')
    refute servers[0].is_main
    assert servers[1].is_main
  end

  # --- self_entry ---

  def test_self_entry_finds_matching_machine_id
    write_machine_id('my-id')

    servers = [
      Server.new(alias_name: 'remote', host: 'r.com', user: nil, port: 22, is_main: false, machine_id: 'other'),
      Server.new(alias_name: 'local', host: nil, user: nil, port: 22, is_main: false, machine_id: 'my-id'),
    ]

    entry = ServerManager.self_entry(servers)
    assert_equal 'local', entry.alias_name
  end

  def test_self_entry_returns_nil_when_no_match
    write_machine_id('my-id')

    servers = [
      Server.new(alias_name: 'remote', host: 'r.com', user: nil, port: 22, is_main: false, machine_id: 'other'),
    ]

    assert_nil ServerManager.self_entry(servers)
  end
end
