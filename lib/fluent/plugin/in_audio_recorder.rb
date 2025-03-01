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
require 'streamio-ffmpeg'
require 'open3'

module Fluent
  module Plugin
    class AudioRecorderInput < Input
      Fluent::Plugin.register_input('audio_recorder', self)

      helpers :timer, :thread

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
      config_param :tag, :string, default: 'audio.recording'

      desc 'Temporary buffer path for audio files'
      config_param :buffer_path, :string, default: '/tmp/fluentd-audio-recorder'

      # Internal class for audio recording and silence detection using FFmpeg
      class Recorder
        def initialize(config, logger)
          @device = config[:device]
          @silence_duration = config[:silence_duration]
          @noise_level = config[:noise_level]
          @min_duration = config[:min_duration]
          @max_duration = config[:max_duration]
          @audio_codec = config[:audio_codec]
          @audio_bitrate = config[:audio_bitrate]
          @audio_sample_rate = config[:audio_sample_rate]
          @audio_channels = config[:audio_channels]
          @buffer_path = config[:buffer_path]
          @log = logger
          @stop_requested = false
        end

        def request_stop
          @stop_requested = true
        end

        def check_ffmpeg
          begin
            `ffmpeg -version`
          rescue => e
            raise Fluent::ConfigError, "FFmpeg is not installed or not in PATH: #{e.message}"
          end
        end

        def record_with_silence_detection
          timestamp = Time.now.strftime("%Y%m%d-%H%M%S_%s")
          output_file = File.join(@buffer_path, "#{timestamp}_#{@device}.#{@audio_codec}")
          
          @log.info "Starting audio recording with silence detection"
          @log.debug "Recording parameters: device=#{@device}, silence_duration=#{@silence_duration}s, noise_level=#{@noise_level}dB, min_duration=#{@min_duration}s, max_duration=#{@max_duration}s"
          
          # FFmpeg command - record with specified codec and perform silence detection
          cmd = [
            "ffmpeg", "-y", "-f", "avfoundation", "-i", ":#{@device}",
            "-af", "silencedetect=noise=#{@noise_level}dB:d=#{@silence_duration}",
            "-ac", @audio_channels.to_s, 
            "-acodec", @audio_codec, 
            "-b:a", @audio_bitrate, 
            "-ar", @audio_sample_rate.to_s, 
            output_file
          ]
          
          start_time = Time.now
          min_time_reached = false
          should_stop = false
          recording_duration = 0
          
          # Execute FFmpeg process and monitor stderr
          Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
            ffmpeg_pid = wait_thr.pid
            
            # State management variables
            silence_start = nil
            
            # Monitor stderr loop
            stderr.each_line do |line|
              # Check for shutdown request
              if @stop_requested
                @log.info "Shutdown requested. Stopping recording."
                Process.kill("INT", ffmpeg_pid) rescue nil
                break
              end

              # Calculate elapsed time
              current_time = Time.now
              elapsed = current_time - start_time
              recording_duration = elapsed
              
              # Check if minimum recording time has been reached
              if !min_time_reached && elapsed >= @min_duration
                min_time_reached = true
                @log.debug "Minimum recording duration (#{@min_duration}s) reached"
              end
              
              # Check for maximum recording time
              if elapsed >= @max_duration
                @log.info "Maximum recording duration (#{@max_duration}s) reached. Stopping recording."
                Process.kill("INT", ffmpeg_pid) rescue nil
                break
              end
              
              # Parse silencedetect output
              if line.include?("silence_start")
                timestamp_match = line.match(/silence_start: ([\d\.]+)/)
                if timestamp_match
                  silence_start = timestamp_match[1].to_f
                  @log.debug "Silence detected at: #{silence_start}s"
                end
              elsif line.include?("silence_end")
                if silence_start && min_time_reached
                  timestamp_match = line.match(/silence_end: ([\d\.]+)/)
                  duration_match = line.match(/silence_duration: ([\d\.]+)/)
                  
                  if timestamp_match && duration_match
                    silence_end = timestamp_match[1].to_f
                    silence_duration_actual = duration_match[1].to_f
                    
                    @log.debug "Silence ended at: #{silence_end}s (duration: #{silence_duration_actual}s)"
                    
                    # If minimum recording time has been exceeded and silence lasted long enough
                    if silence_duration_actual >= @silence_duration
                      @log.info "Valid silence period detected. Stopping recording."
                      should_stop = true
                      Process.kill("INT", ffmpeg_pid) rescue nil
                      break
                    end
                  end
                end
              end
            end
          end
          
          # Verify recording file
          if File.exist?(output_file) && File.size?(output_file) && File.size(output_file) > 1000
            @log.info "Recording completed: #{output_file} (#{recording_duration.round(2)}s)"
            return [output_file, recording_duration]
          else
            @log.warn "Recording file is missing or too small: #{output_file}"
            File.unlink(output_file) if File.exist?(output_file)
            return [nil, 0]
          end
        end
      end

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
        
        @recorder = Recorder.new(config, log)
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
        
        # Example of how to use this in an output plugin:
        #
        # <match audio.recording>
        #   @type file
        #   path /path/to/output/directory/${filename}
        #   # To extract the binary audio content:
        #   <format>
        #     @type single_value
        #     message_key content
        #     add_newline false
        #   </format>
        # </match>
        #
        # Or to use in a custom output plugin:
        # 
        # def process(tag, es)
        #   es.each do |time, record|
        #     filename = record['filename']
        #     audio_data = record['content']  # Already in binary format
        #     # Process the audio data as needed
        #     File.binwrite("/path/to/output/#{filename}", audio_data)
        #   end
        # end
      end
    end
  end
end
