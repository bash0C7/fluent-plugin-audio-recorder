require 'fluent/plugin/input'
require 'fluent/config/error'
require 'fluent/event'  # For EventTime.now
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

      desc 'Interval between recordings (seconds, 0 for continuous recording)'
      config_param :recording_interval, :float, default: 0

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
        @running = false  # Initialize flag to control recording loop
      end

      def multi_workers_ready?
        false
      end

      def zero_downtime_restart_ready?
        false
      end

      def start
        super
        @running = true  # Set flag to true when starting recording
        
        @recording_thread = thread_create(:audio_recording_thread) do
          # Recording loop: continues while plugin is running and @running is true
          while @running && thread_current_running?
            begin
              record_and_emit
            rescue => e
              log.error "Error in audio recording process", error: e.to_s
              log.error_backtrace
              # Short sleep to prevent continuous errors (only if thread is still running)
              sleep 1 if @running && thread_current_running?
            end
            
            # Add sleep between recordings to reduce CPU load (after normal completion)
            sleep @recording_interval if @running && thread_current_running? && @recording_interval > 0
          end
          
          log.info "Audio recording thread has stopped"
        end
      end

      def shutdown
        log.info "Shutting down audio recorder input plugin"
        @running = false  # Set flag to false to stop recording loop
        @recorder.request_stop if @recorder
        
        # Wait for thread to finish (with timeout)
        if @recording_thread
          begin
            log.info "Waiting for recording thread to finish..."
            # Wait for thread to finish for 30 seconds, force shutdown if it takes longer
            Timeout.timeout(30) do
              @recording_thread.join
            end
            log.info "Recording thread finished successfully"
          rescue Timeout::Error
            log.warn "Recording thread did not finish in time, forcing shutdown"
          end
        end
        
        super
      end

      private

      def record_and_emit
        # Call recorder to record audio file with silence detection
        output_file = @recorder.record_with_silence_detection
        if output_file && File.exist?(output_file) && File.size(output_file) > 1000
          log.info "Emitting recorded audio file: #{output_file}"
      
          record = {
            'path' => output_file,
            'filename' => File.basename(output_file), 
            'size' => File.size(output_file),
            'device' => @device, 
            'format' => @audio_codec,
            'content' => File.binread(output_file) # Read file content as binary
          }
          
          router.emit(@tag, Fluent::EventTime.now, record)
        else
          log.debug "No valid recording was produced"
        end
      end
    end
  end
end
