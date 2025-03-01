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

# lib/fluent/plugin/in_audio_recorder.rb の修正内容

require 'fluent/plugin/input'
require 'fluent/config/error'
require 'fileutils'
require 'tempfile'
# require 'logger' # 削除：標準ロガーは使用しない
require 'streamio-ffmpeg'
require 'open3'

module Fluent
  module Plugin
    class AudioRecorderInput < Input
      Fluent::Plugin.register_input('audio_recorder', self)

      helpers :timer

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

      def configure(conf)
        super
        # 一時バッファディレクトリを作成
        FileUtils.mkdir_p(@buffer_path) unless Dir.exist?(@buffer_path)
        log.info "一時バッファディレクトリを作成しました: #{@buffer_path}"
        
        # FFMPEGが利用可能かチェック
        check_ffmpeg
      end

      def start
        super
        # @logger = create_logger # 削除：fluentdのlogを使用するため不要
        @running = true
        @recording_thread = Thread.new(&method(:run))
      end

      def shutdown
        @running = false
        @recording_thread.join if @recording_thread
        super
      end

      private

      # create_loggerメソッドを削除（不要）

      def check_ffmpeg
        begin
          `ffmpeg -version`
        rescue => e
          raise Fluent::ConfigError, "FFmpegがインストールされていないか、パスが通っていません: #{e.message}"
        end
      end

      def run
        begin
          log.info "録音スレッドを開始しました。デバイス: #{@device}"

          # シグナルハンドラを設定
          [:INT, :TERM].each do |signal|
            trap(signal) do
              log.info "シグナル #{signal} を受信しました。録音を停止します。"
              @running = false
            end
          end

          # 録音を続ける
          while @running
            begin
              output_file, duration = record_audio_with_silence_detection
              if output_file && File.exist?(output_file) && File.size(output_file) > 1000
                emit_audio_file(output_file, duration)
              end
            rescue => e
              log.error "録音中にエラーが発生しました: #{e.class} #{e.message}"
              log.error_backtrace(e.backtrace)
              sleep 1  # エラー後の休止
            end
          end
        rescue => e
          log.error "録音スレッドでエラーが発生しました: #{e.class} #{e.message}"
          log.error_backtrace(e.backtrace)
        end
      end

      def record_audio_with_silence_detection
        timestamp = Time.now.strftime("%Y%m%d-%H%M%S_%s")
        output_file = File.join(@buffer_path, "#{timestamp}_#{@device}.#{@audio_codec}")
        
        log.info "無音検出付き録音を開始します:"
        log.info "  デバイス番号: #{@device}"
        log.info "  無音検出閾値: #{@silence_duration}秒"
        log.info "  ノイズレベル: #{@noise_level}dB"
        log.info "  最小録音時間: #{@min_duration}秒"
        log.info "  最大録音時間: #{@max_duration}秒"
        
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
            # 現在のスレッドが停止要求を受けた場合
            unless @running
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
              log.info "最小録音時間(#{@min_duration}秒)に達しました"
            end
            
            # 最大録音時間をチェック
            if elapsed >= @max_duration
              log.info "最大録音時間(#{@max_duration}秒)に達しました。録音を終了します。"
              Process.kill("TERM", ffmpeg_pid) rescue nil
              break
            end
            
            # silencedetectの出力を解析
            if line.include?("silence_start")
              timestamp_match = line.match(/silence_start: ([\d\.]+)/)
              if timestamp_match
                silence_start = timestamp_match[1].to_f
                log.info "無音開始: #{silence_start}秒"
              end
            elsif line.include?("silence_end")
              if silence_start && min_time_reached
                timestamp_match = line.match(/silence_end: ([\d\.]+)/)
                duration_match = line.match(/silence_duration: ([\d\.]+)/)
                
                if timestamp_match && duration_match
                  silence_end = timestamp_match[1].to_f
                  silence_duration_actual = duration_match[1].to_f
                  
                  log.info "無音終了: #{silence_end}秒 (持続時間: #{silence_duration_actual}秒)"
                  
                  # 最小録音時間を超えていて、無音区間が指定時間以上続いた場合
                  if silence_duration_actual >= @silence_duration
                    log.info "有効な無音区間を検出しました。録音を終了します。"
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
          log.info "録音完了: #{output_file} (#{recording_duration.round(2)}秒)"
          return [output_file, recording_duration]
        else
          log.warn "録音ファイルが見つからないか、サイズが小さすぎます: #{output_file}"
          File.unlink(output_file) if File.exist?(output_file)
          return [nil, 0]
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
