# frozen_string_literal: true

require_relative 'test_helper'

class TestRunWithTimeout < TSMTestCase
  def test_successful_command
    result = run_with_timeout("echo hello", 5)
    assert_equal "hello\n", result
  end

  def test_returns_empty_on_timeout
    result = run_with_timeout("sleep 10", 1)
    assert_equal "", result
  end

  def test_captures_stderr
    result = run_with_timeout("echo err >&2", 5)
    assert_includes result, "err"
  end

  def test_utf8_encoding
    result = run_with_timeout("echo test", 5)
    assert_equal Encoding::UTF_8, result.encoding
  end

  def test_handles_nonzero_exit
    result = run_with_timeout("echo output && false", 5)
    assert_includes result, "output"
  end

  def test_multiline_output
    result = run_with_timeout("echo line1; echo line2", 5)
    assert_includes result, "line1"
    assert_includes result, "line2"
  end
end
