require "helper"
require "fluent/plugin/in_audio_recorder.rb"
require "fileutils"

class AudioRecorderInputTest < Test::Unit::TestCase
  # Mock recorder class that returns a predefined audio file
  class MockRecorder
    attr_reader :recorded_file_path
    attr_accessor :stop_requested
    
    def initialize(recorded_file_path)
      @recorded_file_path = recorded_file_path
      @stop_requested = false
    end
    
    def record_with_silence_detection
      @recorded_file_path
    end
    
    def request_stop
      @stop_requested = true
    end
  end

  TEST_DIR = File.join(File.dirname(__FILE__), "tmp", "audio_recorder_test")
  
  setup do
    Fluent::Test.setup
    # Ensure test directory exists
    FileUtils.mkdir_p(TEST_DIR)
  end

  teardown do
    # Clean up test directory after tests
    FileUtils.rm_rf(TEST_DIR) if File.exist?(TEST_DIR)
  end

  sub_test_case "default configuration" do
    test "should set default parameters correctly" do
      # Create plugin driver with default configuration
      driver = Fluent::Test::Driver::Input.new(Fluent::Plugin::AudioRecorderInput).configure("")
      
      # Verify all default parameter values
      assert_equal 0, driver.instance.device
      assert_equal 1.0, driver.instance.silence_duration
      assert_equal(-30, driver.instance.noise_level)
      assert_equal 2, driver.instance.min_duration
      assert_equal 900, driver.instance.max_duration
      assert_equal 'aac', driver.instance.audio_codec
      assert_equal '192k', driver.instance.audio_bitrate
      assert_equal 44100, driver.instance.audio_sample_rate
      assert_equal 1, driver.instance.audio_channels
      assert_equal 'audio_recorder.recording', driver.instance.tag
      assert_equal 0.0, driver.instance.recording_interval
    end
  end

  sub_test_case "custom configuration" do
    test "should override default parameters with custom values" do
      # Create plugin driver with custom configuration
      config = %[
        device 1
        silence_duration 2.5
        noise_level -25
        min_duration 5
        max_duration 300
        audio_codec mp3
        audio_bitrate 256k
        audio_sample_rate 48000
        audio_channels 2
        tag custom.audio
        buffer_path #{TEST_DIR}
        recording_interval 0.5
      ]
      
      driver = Fluent::Test::Driver::Input.new(Fluent::Plugin::AudioRecorderInput).configure(config)
      
      # Verify all custom parameter values
      assert_equal 1, driver.instance.device
      assert_equal 2.5, driver.instance.silence_duration
      assert_equal(-25, driver.instance.noise_level)
      assert_equal 5, driver.instance.min_duration
      assert_equal 300, driver.instance.max_duration
      assert_equal 'mp3', driver.instance.audio_codec
      assert_equal '256k', driver.instance.audio_bitrate
      assert_equal 48000, driver.instance.audio_sample_rate
      assert_equal 2, driver.instance.audio_channels
      assert_equal 'custom.audio', driver.instance.tag
      assert_equal TEST_DIR, driver.instance.buffer_path
      assert_equal 0.5, driver.instance.recording_interval
    end
  end

  sub_test_case "recording and emitting" do
    test "should emit event with correct audio metadata and content" do
      # Arrange: Setup driver and create test audio file
      driver = Fluent::Test::Driver::Input.new(Fluent::Plugin::AudioRecorderInput).configure(%[
        device 0
        buffer_path #{TEST_DIR}
      ])

      # Create a test audio file
      test_file_path = File.join(TEST_DIR, "test_audio.aac")
      test_content = "dummy audio content" * 100  # Make the file size > 1000 bytes
      File.open(test_file_path, "wb") do |f|
        f.write(test_content)
      end
      
      # Replace the actual recorder with our mock
      mock_recorder = MockRecorder.new(test_file_path)
      driver.instance.instance_variable_set(:@recorder, mock_recorder)
      
      # Act: Run the input plugin to trigger recording and event emission
      driver.run(expect_emits: 1, timeout: 1)
      
      # Assert: Verify emitted events
      events = driver.events
      
      tag, time, record = events.first
      
      # Verify the event tag
      assert_equal "audio_recorder.recording", tag
      
      # Verify event has a valid timestamp
      assert time, "Event should have a timestamp"
      
      # Verify record fields
      assert_equal "test_audio.aac", record["filename"]
      assert_equal test_file_path, record["path"]
      assert_equal test_content.bytesize, record["size"]
      assert_equal 0, record["device"]
      assert_equal "aac", record["format"]
      
      # Verify the binary content matches the original file
      original_content = File.binread(test_file_path)
      assert_equal original_content, record["content"], "Binary content should match the original file"
    end
    
    test "should handle recording shutdown properly" do
      # Arrange: Setup driver
      driver = Fluent::Test::Driver::Input.new(Fluent::Plugin::AudioRecorderInput).configure(%[
        device 0
        buffer_path #{TEST_DIR}
      ])
      
      # Create a mock recorder
      mock_recorder = MockRecorder.new(nil)
      driver.instance.instance_variable_set(:@recorder, mock_recorder)
      
      # Act: Run and then shutdown
      thread = Thread.new { driver.run }
      sleep 0.1 # Give the plugin a moment to start
      
      driver.instance.shutdown
      thread.join(1) # Wait for thread with timeout
      
      # Assert: Verify shutdown requested flag was set
      assert_true mock_recorder.stop_requested, "Stop should have been requested from recorder"
    end
  end
end
