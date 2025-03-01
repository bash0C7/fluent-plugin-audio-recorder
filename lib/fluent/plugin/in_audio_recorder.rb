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

      desc 'デバイス番号'
      config_param :device, :integer, default: 0

      desc '無音と判断する秒数'
      config_param :silence_duration, :float, default: 1.0

      desc '無音と判断するノイズレベル(dB)'
      config_param :noise_level, :integer, default: -30

      desc '最小録音時間(秒)'
      config_param :min_duration, :integer, default: 2

      desc '最大録音時間(秒)'
      config_param :max_duration, :integer, default: 900  # デフォルト15分

      desc '音声コーデック'
      config_param :audio_codec, :string, default: 'aac'

      desc '音声ビットレート'
      config_param :audio_bitrate, :string, default: '192k'

      desc '音声サンプルレート'
      config_param :audio_sample_rate, :integer, default: 44100

      desc '音声チャンネル数'
      config_param :audio_channels, :integer, default: 1

      desc 'タグ'
      config_param :tag, :string, default: 'audio.recording'

      desc '一時ファイル保存パス'
      config_param :buffer_path, :string, default: '/tmp/fluentd-audio-recorder'

      # FFmpegを利用した音声録音と無音検出を行う内部クラス
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
            raise Fluent::ConfigError, "FFmpegがインストールされていないか、パスが通っていません: #{e.message}"
          end
        end

        def record_with_silence_detection
          timestamp = Time.now.strftime("%Y%m%d-%H%M%S_%s")
          output_file = File.join(@buffer_path, "#{timestamp}_#{@device}.#{@audio_codec}")
          
          @log.info "無音検出付き録音を開始します:"
          @log.info "  デバイス番号: #{@device}"
          @log.info "  無音検出閾値: #{@silence_duration}秒"
          @log.info "  ノイズレベル: #{@noise_level}dB"
          @log.info "  最小録音時間: #{@min_duration}秒"
          @log.info "  最大録音時間: #{@max_duration}秒"
          
          # FFmpegコマンド - 指定されたコーデックで録音しながら無音検出も実行
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
          
          # FFmpegプロセスを実行して標準エラー出力を監視
          Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
            ffmpeg_pid = wait_thr.pid
            
            # 状態管理変数
            silence_start = nil
            
            # 標準エラー出力の監視ループ
            stderr.each_line do |line|
              # シャットダウンが要求された場合
              if @stop_requested
                @log.info "シャットダウン要求を受信しました。録音を終了します。"
                Process.kill("INT", ffmpeg_pid) rescue nil
                break
              end

              # 経過時間を計算
              current_time = Time.now
              elapsed = current_time - start_time
              recording_duration = elapsed
              
              # 最小録音時間に達したかチェック
              if !min_time_reached && elapsed >= @min_duration
                min_time_reached = true
                @log.info "最小録音時間(#{@min_duration}秒)に達しました"
              end
              
              # 最大録音時間をチェック
              if elapsed >= @max_duration
                @log.info "最大録音時間(#{@max_duration}秒)に達しました。録音を終了します。"
                Process.kill("INT", ffmpeg_pid) rescue nil
                break
              end
              
              # silencedetectの出力を解析
              if line.include?("silence_start")
                timestamp_match = line.match(/silence_start: ([\d\.]+)/)
                if timestamp_match
                  silence_start = timestamp_match[1].to_f
                  @log.info "無音開始: #{silence_start}秒"
                end
              elsif line.include?("silence_end")
                if silence_start && min_time_reached
                  timestamp_match = line.match(/silence_end: ([\d\.]+)/)
                  duration_match = line.match(/silence_duration: ([\d\.]+)/)
                  
                  if timestamp_match && duration_match
                    silence_end = timestamp_match[1].to_f
                    silence_duration_actual = duration_match[1].to_f
                    
                    @log.info "無音終了: #{silence_end}秒 (持続時間: #{silence_duration_actual}秒)"
                    
                    # 最小録音時間を超えていて、無音区間が指定時間以上続いた場合
                    if silence_duration_actual >= @silence_duration
                      @log.info "有効な無音区間を検出しました。録音を終了します。"
                      should_stop = true
                      Process.kill("INT", ffmpeg_pid) rescue nil
                      break
                    end
                  end
                end
              end
            end
          end
          
          # 録音ファイルの確認
          if File.exist?(output_file) && File.size?(output_file) && File.size(output_file) > 1000
            @log.info "録音完了: #{output_file} (#{recording_duration.round(2)}秒)"
            return [output_file, recording_duration]
          else
            @log.warn "録音ファイルが見つからないか、サイズが小さすぎます: #{output_file}"
            File.unlink(output_file) if File.exist?(output_file)
            return [nil, 0]
          end
        end
      end

      def configure(conf)
        super
        # 一時バッファディレクトリを作成
        FileUtils.mkdir_p(@buffer_path) unless Dir.exist?(@buffer_path)
        log.info "一時バッファディレクトリを作成しました: #{@buffer_path}"
        
        # Recorderインスタンスの生成
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
          # 録音ループ：プラグインが動作している間は続ける
          begin
            until thread_stopped?
              record_and_emit
            end
          rescue => e
            log.error "録音スレッドでエラーが発生しました", error: e
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
          log.error "録音中にエラーが発生しました", error: e
          log.error_backtrace
        end
      end

      def emit_audio_file(file_path, duration)
        log.info "録音ファイルをストリームに流します: #{file_path}"
        
        time = Fluent::Engine.now
        
        record = {
          'path' => file_path,
          'size' => File.size(file_path),
          'timestamp' => Time.now.to_i,
          'device' => @device,
          'duration' => duration.round(2),
          'format' => @audio_codec
        }
        
        router.emit(@tag, time, record)
      end
    end
  end
end
