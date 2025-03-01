#
# Copyright 2025- bash0C7
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/input'
require 'fluent/config/error'
require 'fileutils'
require 'tempfile'
require_relative 'audio_recorder/recorder'

module Fluent
  module Plugin
    class AudioRecorderInput < Input
      Fluent::Plugin.register_input('audio_recorder', self)

      helpers :thread

      desc 'Device number for recording'
      config_param :device, :integer, default: 0

      desc 'Duration of silence to trigger stop recording (seconds)'
      config_param :silence_duration, :float, default: 1.0

      desc 'Noise level threshold for silence detection (dB)'
      config_param :noise_level, :integer, default: -30

      desc 'Minimum recording duration (seconds)'
      config_param :min_duration, :integer, default: 2

      desc 'Maximum recording duration (seconds)'
      config_param :max_duration, :integer, default: 900  # Default 15 minutes

      desc 'Audio codec'
      config_param :audio_codec, :string, default: 'aac'

      desc 'Audio bitrate'
      config_param :audio_bitrate, :string, default: '192k'

      desc 'Audio sample rate'
      config_param :audio_sample_rate, :integer, default: 44100

      desc 'Audio channels'
      config_param :audio_channels, :integer, default: 1

      desc 'Tag for emitted events'
      config_param :tag, :string, default: 'audio_recorder.recording'

      desc 'Temporary buffer path for audio files'
      config_param :buffer_path, :string, default: '/tmp/fluentd-audio-recorder'

      def configure(conf)
        super
        # Create temporary buffer directory
        FileUtils.mkdir_p(@buffer_path) unless Dir.exist?(@buffer_path)
        log.info "Created temporary buffer directory: #{@buffer_path}"
        
        # Create Recorder instance
        config = {
          device: @device,
          silence_duration: @silence_duration,
          noise_level: @noise_level,
          min_duration: @min_duration,
          max_duration: @max_duration,
          audio_codec: @audio_codec,
          audio_bitrate: @audio_bitrate,
          audio_sample_rate: @audio_sample_rate,
          audio_channels: @audio_channels,
          buffer_path: @buffer_path
        }
        
        @recorder = AudioRecorder::Recorder.new(config, log)
        @recorder.check_ffmpeg
      end

      def multi_workers_ready?
        true
      end

      def start
        super
        @recording_thread = thread_create(:audio_recording_thread) do
          # Recording loop: continues while plugin is running
          begin
            until thread_stopped?
              record_and_emit
            end
          rescue => e
            log.error "Error in recording thread", error: e
            log.error_backtrace
          end
        end
      end

      def shutdown
        @recorder.request_stop if @recorder
        @recording_thread.join if @recording_thread
        super
      end

      private

      def record_and_emit
        begin
          output_file, duration = @recorder.record_with_silence_detection
          if output_file && File.exist?(output_file) && File.size(output_file) > 1000
            emit_audio_file(output_file, duration)
          end
        rescue => e
          log.error "Error during recording", error: e
          log.error_backtrace
        end
      end

      def emit_audio_file(file_path, duration)
        log.info "Emitting recorded audio file: #{file_path}"
        
        time = Fluent::Engine.now
        
        # Read file content as binary
        file_content = File.binread(file_path)
        
        # Extract just the filename with extension from the path
        filename = File.basename(file_path)
        
        record = {
          'path' => file_path,
          'filename' => filename,
          'size' => File.size(file_path),
          'timestamp' => Time.now.to_i,
          'device' => @device,
          'duration' => duration.round(2),
          'format' => @audio_codec,
          'content' => file_content
        }
        
        router.emit(@tag, time, record)
      end
    end
  end
end
