require "helper"
require "fluent/plugin/in_audio_recorder.rb"
require "fileutils"

class AudioRecorderInputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
    @tmp_dir = File.join(File.dirname(__FILE__), "tmp", "audio_recorder_test")
    FileUtils.mkdir_p(@tmp_dir)
  end

  teardown do
    FileUtils.rm_rf(@tmp_dir) if File.exist?(@tmp_dir)
  end

  sub_test_case "configure" do
    test "with default parameters" do
      d = create_driver
      assert_equal 0, d.instance.device
      assert_equal 1.0, d.instance.silence_duration
      assert_equal -30, d.instance.noise_level
      assert_equal 2, d.instance.min_duration
      assert_equal 900, d.instance.max_duration
      assert_equal 'aac', d.instance.audio_codec
      assert_equal '192k', d.instance.audio_bitrate
      assert_equal 44100, d.instance.audio_sample_rate
      assert_equal 1, d.instance.audio_channels
      assert_equal 'audio.recording', d.instance.tag
    end

    test "with custom parameters" do
      d = create_driver(%[
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
        buffer_path #{@tmp_dir}
      ])

      assert_equal 1, d.instance.device
      assert_equal 2.5, d.instance.silence_duration
      assert_equal -25, d.instance.noise_level
      assert_equal 5, d.instance.min_duration
      assert_equal 300, d.instance.max_duration
      assert_equal 'mp3', d.instance.audio_codec
      assert_equal '256k', d.instance.audio_bitrate
      assert_equal 48000, d.instance.audio_sample_rate
      assert_equal 2, d.instance.audio_channels
      assert_equal 'custom.audio', d.instance.tag
      assert_equal @tmp_dir, d.instance.buffer_path
    end
  end

  sub_test_case "recording and emitting" do
    test "recording workflow" do
      d = create_driver(%[
        device 0
        buffer_path #{@tmp_dir}
      ])

      # Create a mock Recorder class to avoid actual FFmpeg calls
      mock_recorder = Struct.new(:record_with_silence_detection, :request_stop).new(
        -> { [test_file_path, test_duration] },
        -> { true }
      )
      
      # Create a test audio file
      test_file_path = File.join(@tmp_dir, "test_audio.aac")
      test_duration = 10.5
      test_content = "dummy audio content" * 100  # Make the file size > 1000 bytes
      
      File.open(test_file_path, "w") do |f|
        f.write(test_content)
      end

      # Replace the recorder with our mock
      d.instance.instance_variable_set(:@recorder, mock_recorder)
      
      # Run the input plugin and capture emitted events
      d.run(expect_emits: 1, timeout: 5) do
        # Simulate the record_and_emit method directly
        d.instance.send(:record_and_emit)
      end
      
      # Verify emitted events
      events = d.events
      assert_equal 1, events.size
      
      tag, time, record = events[0]
      assert_equal "audio.recording", tag
      assert_equal "test_audio.aac", record["filename"]
      assert_equal test_file_path, record["path"]
      assert_equal test_duration.round(2), record["duration"]
      assert_equal "aac", record["format"]
      assert_true record.has_key?("content")
      assert_true record.has_key?("size")
      assert_true record.has_key?("timestamp")
      
      # Verify the binary content is passed through correctly
      original_content = File.binread(test_file_path)
      assert_equal original_content, record["content"]
    end
  end

  private

  def create_driver(conf = "")
    Fluent::Test::Driver::Input.new(Fluent::Plugin::AudioRecorderInput).configure(conf)
  end
end
