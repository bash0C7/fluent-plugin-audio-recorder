require 'open3'
require 'fileutils'

module Fluent
  module Plugin
    module AudioRecorder
      # Class for audio recording and silence detection using FFmpeg
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
            return output_file
          else
            @log.warn "Recording file is missing or too small: #{output_file}"
            return nil
          end
        end
      end
    end
  end
end
