require 'open3'
require 'fileutils'

module Fluent
  module Plugin
    module AudioRecorder
      # Class for audio recording and silence detection using FFmpeg
      class Recorder
        def initialize(config)
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
          @stop_requested = false
        end

        def request_stop
          @stop_requested = true
        end

        def record_with_silence_detection
          timestamp = Time.now.strftime("%Y%m%d-%H%M%S_%s")
          output_file = File.join(@buffer_path, "#{timestamp}_#{@device}.#{@audio_codec}")
          
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
          
          # Execute FFmpeg process and monitor stderr
          Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
            ffmpeg_pid = wait_thr.pid
            
            # State management variables
            silence_start = nil
            
            # Monitor stderr loop
            stderr.each_line do |line|
              # Check for shutdown request
              if @stop_requested
                Process.kill("INT", ffmpeg_pid) rescue nil
                break
              end

              # Calculate elapsed time and check limits
              elapsed = Time.now - start_time
              
              # Check for maximum recording time
              if elapsed >= @max_duration
                Process.kill("INT", ffmpeg_pid) rescue nil
                break
              end
              
              # Check if minimum recording time has been reached
              min_time_reached = true if !min_time_reached && elapsed >= @min_duration
              
              # Parse silencedetect output
              if line.include?("silence_start")
                timestamp_match = line.match(/silence_start: ([\d\.]+)/)
                silence_start = timestamp_match[1].to_f if timestamp_match
              elsif line.include?("silence_end") && silence_start && min_time_reached
                timestamp_match = line.match(/silence_end: ([\d\.]+)/)
                duration_match = line.match(/silence_duration: ([\d\.]+)/)
                
                if timestamp_match && duration_match
                  silence_duration_actual = duration_match[1].to_f
                  
                  # If silence lasted long enough, stop recording
                  if silence_duration_actual >= @silence_duration
                    Process.kill("INT", ffmpeg_pid) rescue nil
                    break
                  end
                end
              end
            end
          end
          
          # Verify recording file
          if File.exist?(output_file) && File.size(output_file) > 1000
            return output_file
          else
            return nil
          end
        end
      end
    end
  end
end
