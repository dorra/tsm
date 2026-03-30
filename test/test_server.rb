# frozen_string_literal: true

require_relative 'test_helper'

class TestServer < TSMTestCase
  def setup
    super
    write_machine_id('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')
  end

  # --- local? ---

  def test_local_when_machine_id_matches
    server = Server.new(
      alias_name: 'mybox', host: 'mybox.local', user: 'me', port: 22,
      is_main: false, machine_id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    )
    assert server.local?
  end

  def test_not_local_when_machine_id_differs
    server = Server.new(
      alias_name: 'remote', host: 'remote.example.com', user: 'deploy', port: 22,
      is_main: false, machine_id: '11111111-2222-3333-4444-555555555555'
    )
    refute server.local?
  end

  def test_local_legacy_nil_host
    server = Server.new(
      alias_name: 'local', host: nil, user: nil, port: 22,
      is_main: false, machine_id: nil
    )
    assert server.local?
  end

  def test_local_legacy_empty_host
    server = Server.new(
      alias_name: 'local', host: '', user: nil, port: 22,
      is_main: false, machine_id: nil
    )
    assert server.local?
  end

  def test_local_legacy_localhost
    server = Server.new(
      alias_name: 'local', host: 'localhost', user: nil, port: 22,
      is_main: false, machine_id: nil
    )
    assert server.local?
  end

  # --- display_name ---

  def test_display_name_without_main
    server = Server.new(alias_name: 'prod', host: 'prod.com', user: nil, port: 22, is_main: false, machine_id: nil)
    assert_equal 'prod', server.display_name
  end

  def test_display_name_with_main
    server = Server.new(alias_name: 'prod', host: 'prod.com', user: nil, port: 22, is_main: true, machine_id: nil)
    assert_equal 'prod [main]', server.display_name
  end

  # --- ssh_target ---

  def test_ssh_target_with_user
    server = Server.new(
      alias_name: 'prod', host: 'prod.example.com', user: 'deploy', port: 22,
      is_main: false, machine_id: '11111111-2222-3333-4444-555555555555'
    )
    assert_equal 'deploy@prod.example.com', server.ssh_target
  end

  def test_ssh_target_without_user
    server = Server.new(
      alias_name: 'prod', host: 'prod.example.com', user: nil, port: 22,
      is_main: false, machine_id: '11111111-2222-3333-4444-555555555555'
    )
    assert_equal 'prod.example.com', server.ssh_target
  end

  def test_ssh_target_local_returns_nil
    server = Server.new(
      alias_name: 'local', host: nil, user: nil, port: 22,
      is_main: false, machine_id: nil
    )
    assert_nil server.ssh_target
  end

  def test_ssh_target_empty_user
    server = Server.new(
      alias_name: 'prod', host: 'prod.example.com', user: '', port: 22,
      is_main: false, machine_id: '11111111-2222-3333-4444-555555555555'
    )
    assert_equal 'prod.example.com', server.ssh_target
  end

  # --- to_line ---

  def test_to_line_full_server
    server = Server.new(
      alias_name: 'prod', host: 'prod.example.com', user: 'deploy', port: 2222,
      is_main: true, machine_id: 'abc-123'
    )
    assert_equal 'prod|prod.example.com|deploy|2222|true|abc-123', server.to_line
  end

  def test_to_line_local_server
    server = Server.new(
      alias_name: 'local', host: nil, user: nil, port: 22,
      is_main: false, machine_id: 'abc-123'
    )
    assert_equal 'local|||22|false|abc-123', server.to_line
  end

  def test_to_line_no_machine_id
    server = Server.new(
      alias_name: 'legacy', host: nil, user: nil, port: 22,
      is_main: false, machine_id: nil
    )
    assert_equal 'legacy|||22|false|', server.to_line
  end
end
